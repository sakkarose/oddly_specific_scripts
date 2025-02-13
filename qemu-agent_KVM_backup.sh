#!/bin/bash

# --- Configuration ---
BACKUP_DIR="/home/backup-str"  # Replace with your backup directory
RETENTION_DAYS=7  # Keep backups for 7 days
FULL_BACKUP_INTERVAL=7 # Create a full backup every 7 backups
LOG_FILE="$BACKUP_DIR/log"  # Replace with your desired log file path
LOCK_FILE="/var/run/vm-backup.lock"  # Lock file for concurrent backup handling
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB max log size

# --- Functions ---

# Set up proper output handling
setup_output() {
    # Save original stdout/stderr
    exec 3>&1 4>&2
    
    # If running interactively, use immediate output
    if [[ -t 1 ]]; then
        # Use line buffering for interactive mode
        export PYTHONUNBUFFERED=1
        export PERL_BULK_FLUSH=1
        # Redirect stdout/stderr to both console and log
        exec 1> >(tee -a "$LOG_FILE")
        exec 2> >(tee -a "$LOG_FILE" >&2)
    else
        # In non-interactive mode, just log to file
        exec 1>>"$LOG_FILE" 2>&1
    fi
}

# Fix log function to prevent double logging
log() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp - $message"
}

# Fix log rotation function
rotate_log() {
    if [[ -f "$LOG_FILE" ]]; then
        local current_size=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")
        if (( current_size >= MAX_LOG_SIZE )); then
            local readable_size
            readable_size=$(numfmt --to=iec-i --suffix=B "${MAX_LOG_SIZE}" 2>/dev/null || echo "${MAX_LOG_SIZE} bytes")
            log "Log file reached max size ($readable_size). Rotating..."
            local rotation_date=$(date +%d%m%Y)
            local rotated_log_name="${LOG_FILE}-${rotation_date}"
            mv "$LOG_FILE" "$rotated_log_name"
            touch "$LOG_FILE"
        fi
    fi
}

# Call setup_output at script start
setup_output

check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        log "Another backup process is running. Exiting."
        exit 1
    fi
    touch "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' EXIT
}

check_disk_space() {
    local required_space=$1
    local available_space=$(df -B1 "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt "$required_space" ]; then
        log "Error: Insufficient disk space. Required: $required_space, Available: $available_space"
        exit 1
    fi
}

validate_vm() {
    local vm_name="$1"
    if ! virsh dominfo "$vm_name" >/dev/null 2>&1; then
        log "Error: VM $vm_name does not exist"
        exit 1
    fi
}

# Add new function to reset VM disk state
reset_vm_disk_state() {
    local VM_NAME="$1"
    log "Attempting to reset VM disk state..."
    
    # Get original disk path directly from the VM XML
    local original_disk
    original_disk=$(virsh dumpxml "$VM_NAME" | xmllint --xpath "string(//disk[@device='disk']/source/@file)" - 2>/dev/null)
    
    if [[ -z "$original_disk" ]]; then
        log "Error: Could not determine original disk path from XML"
        return 1
    fi
    
    log "Found original disk: $original_disk"
    
    # Stop VM if running
    if virsh domstate "$VM_NAME" | grep -q "running"; then
        log "Stopping VM..."
        virsh destroy "$VM_NAME"
    fi
    
    # Remove all snapshots, including external ones
    log "Removing snapshots..."
    virsh snapshot-list "$VM_NAME" --name 2>/dev/null | while read -r snap; do
        log "Removing snapshot: $snap"
        # Try metadata-only removal first
        virsh snapshot-delete "$VM_NAME" "$snap" --metadata 2>/dev/null || true
        # Then try full removal
        virsh snapshot-delete "$VM_NAME" "$snap" 2>/dev/null || true
    done
    
    # Get current disks to clean up
    local current_disks
    current_disks=$(virsh domblklist "$VM_NAME" | awk 'NR>2 && $2!="" {print $2}')
    
    # Update VM configuration
    log "Updating VM configuration..."
    virsh dumpxml "$VM_NAME" > /tmp/vm_config.xml
    
    # Update disk paths in the XML
    sed -i "s|<source file='[^']*'/>|<source file='$original_disk'/>|g" /tmp/vm_config.xml
    sed -i "s|<source file=\"[^\"]*\"/>|<source file=\"$original_disk\"/>|g" /tmp/vm_config.xml
    
    # Undefine and redefine the VM
    virsh destroy "$VM_NAME" 2>/dev/null || true
    virsh undefine "$VM_NAME" --nvram --snapshots-metadata 2>/dev/null || true
    virsh define /tmp/vm_config.xml
    rm -f /tmp/vm_config.xml
    
    # Clean up any leftover snapshot files
    while read -r disk_file; do
        if [[ "$disk_file" != "$original_disk" && -f "$disk_file" ]]; then
            log "Removing leftover disk file: $disk_file"
            rm -f "$disk_file"
        fi
    done <<< "$current_disks"
    
    log "VM disk state reset complete. Original disk path: $original_disk"
    return 0
}

backup_vm() {
    local VM_NAME="$1"
    local BACKUP_TYPE="$2" # "live" or "offline"

    validate_vm "$VM_NAME"

    if [[ "$BACKUP_TYPE" != "live" && "$BACKUP_TYPE" != "offline" ]]; then
        log "Error: Invalid backup type. Use 'live' or 'offline'." >&3
        exit 1
    fi

    # Check for snapshot state at the start
    if virsh dumpxml "$VM_NAME" | grep -q "snapshot.*qcow2"; then
        log "VM is in snapshot state. Attempting to reset..."
        reset_vm_disk_state "$VM_NAME" || {
            log "Error: Failed to reset VM disk state. Please reset manually."
            exit 1
        }
        log "VM reset successful. Continuing with backup..."
    fi

    # Fix timestamp handling
    local date_folder=$(date +%d%m%Y)
    local timestamp=$(date +%d%m%Y_%H%M%S)
    
    # Create date-based backup directory
    local VM_BACKUP_DIR="$BACKUP_DIR/$VM_NAME/$date_folder"
    mkdir -p "$VM_BACKUP_DIR" || { log "Error: Could not create backup directory: $VM_BACKUP_DIR"; exit 1; }

    log "Starting $BACKUP_TYPE backup of $VM_NAME..."
    local timestamp=$(date +%d%m%Y)

    # Improved disk detection with better error handling
    log "Detecting disks for VM $VM_NAME..."
    
    # Improved disk detection using XML parsing
    local xml_disks
    xml_disks=$(virsh dumpxml "$VM_NAME" | awk '
        /<disk.*type=.file/,/<\/disk>/ {
            if ($0 ~ /source file=/) {
                gsub(/.*file=.[^"'\'']*["\x27]([^"'\'']+)["\x27].*/, "\\1")
                print
            }
        }
    ')
    
    # Get current disk mapping with better filtering
    local disks
    disks=$(virsh domblklist "$VM_NAME" 2>/dev/null | awk -v vm="$VM_NAME" '
        NR>2 {
            if ($1 && $2 && ($1 ~ /^[hvs]d[a-z][0-9]*$/ || $1 ~ /^nvme[0-9]+n[0-9]+(p[0-9]+)?$/)) {
                if ($2 !~ /snapshot/) {
                    print $1, $2
                }
            }
        }
    ')

    if [[ -z "$disks" ]]; then
        log "Error: No valid disks found. Dumping debug information:"
        log "XML configuration:"
        virsh dumpxml "$VM_NAME" | grep -A5 "<disk" >&2
        log "Current block devices:"
        virsh domblklist "$VM_NAME" >&2
        exit 1
    fi

    # Debug output
    log "Found disks:"
    while read -r disk target; do
        log "Device: $disk -> $target"
    done <<< "$disks"

    # Reset VM to original disk configuration if needed
    while read -r disk target; do
        if [[ "$target" == *"snapshot"* ]]; then
            log "Warning: Found snapshot disk, attempting to reset VM configuration..."
            virsh snapshot-delete "$VM_NAME" --current --metadata 2>/dev/null || true
            virsh snapshot-delete "$VM_NAME" --current 2>/dev/null || true
            log "Please try running the backup again."
            exit 1
        fi
    done <<< "$disks"

    # Verify disk paths exist
    while read -r disk target; do
        if [[ ! -f "$target" ]]; then
            log "Error: Disk file not found: $target for disk $disk"
            exit 1
        fi
    done <<< "$disks"

    # Calculate required space (rough estimate)
    local total_disk_size=0
    while read -r disk target; do
        local size=$(qemu-img info "$target" | grep 'virtual size' | awk '{print $4}')
        total_disk_size=$((total_disk_size + size))
    done <<< "$disks"

    check_disk_space "$total_disk_size"

    # Offline Backup: Shutdown VM if running.
    if [[ "$BACKUP_TYPE" == "offline" && $(virsh domstate "$VM_NAME" 2>&3 | grep -q running) ]]; then
        log "Shutting down VM for offline backup..."
        virsh shutdown "$VM_NAME" || { log "Warning: Shutdown command may have failed."; }
        local timeout=60
        local start_time=$(date +%s)

        while virsh domstate "$VM_NAME" 2>&3 | grep -q running; do
            sleep 1
            local elapsed_time=$(( $(date +%s) - start_time ))
            if [[ "$elapsed_time" -gt "$timeout" ]]; then
                log "Warning: VM failed to shut down gracefully.  Forcing power off."
                virsh destroy "$VM_NAME" || { log "Error: Failed to destroy VM"; exit 1; }
                break
            fi
        done
    fi

    # --- Backup Process ---
    while read -r disk target; do
        # Keep chain file in VM root for consistency
        local VM_ROOT_DIR="$BACKUP_DIR/$VM_NAME"
        local BACKUP_CHAIN_FILE="$VM_ROOT_DIR/${VM_NAME}_${disk}_chain.txt"
        
        # Verify chain file directory exists
        mkdir -p "$VM_ROOT_DIR"

        # Add chain file validation
        if [[ -f "$BACKUP_CHAIN_FILE" ]]; then
            while read -r bfile btime; do
                if [[ ! -f "$bfile" ]]; then
                    log "Warning: Backup file missing from chain: $bfile"
                    full_backup_needed=true
                    break
                fi
            done < "$BACKUP_CHAIN_FILE"
        fi

        # Improved checkpoint handling
        log "Checking for existing checkpoints..."
        if virsh checkpoint-list "$VM_NAME" --name 2>/dev/null | grep -q .; then
            log "Warning: Checkpoints exist for VM $VM_NAME. Deleting..."
            
            # Get list of checkpoints and delete them one by one
            virsh checkpoint-list "$VM_NAME" --name 2>/dev/null | while read -r checkpoint; do
                if [[ -n "$checkpoint" ]]; then
                    log "Deleting checkpoint: $checkpoint"
                    virsh checkpoint-delete "$VM_NAME" "$checkpoint" || {
                        log "Warning: Failed to delete checkpoint $checkpoint"
                        continue
                    }
                fi
            done
        fi

        # Determine if it's a full or incremental backup.  More robust check.
        local full_backup_needed=false
        if [[ ! -f "$BACKUP_CHAIN_FILE" ]]; then
            full_backup_needed=true
        else
            local last_backup_time=$(tail -n 1 "$BACKUP_CHAIN_FILE" 2>/dev/null | cut -d' ' -f2 || echo 0)
            if [[ "$(($(date +%s) - last_backup_time))" -ge "$((FULL_BACKUP_INTERVAL * 24 * 60 * 60))" ]]; then
                full_backup_needed=true
            fi
        fi

        if "$full_backup_needed"; then
            # Full backup
            local backup_file="$VM_BACKUP_DIR/$VM_NAME-${timestamp}_${disk}_full.qcow2"
            log "Performing full backup for $disk..."

            if [[ "$BACKUP_TYPE" == "live" ]]; then
                # Live Full Backup using snapshot
                local snapshot_file="$VM_BACKUP_DIR/$VM_NAME-${timestamp}_${disk}_snapshot.qcow2"
                virsh snapshot-create-as --domain "$VM_NAME" --name "backup_snapshot_$disk" \
                  --description "Backup snapshot" --disk-only --atomic \
                  --diskspec "$disk,file=$snapshot_file" || { log "Error: Snapshot creation failed for $disk"; exit 1; }

                qemu-img convert -f qcow2 -O qcow2 -c "$snapshot_file" "$backup_file" || { log "Error: qemu-img convert failed for $disk"; exit 1; }
                # Use --diskspec for deletion: More robust.
                virsh snapshot-delete "$VM_NAME" "backup_snapshot_$disk" --diskspec "$disk" || { log "Warning: Snapshot deletion failed for $disk"; exit 1; }

            elif [[ "$BACKUP_TYPE" == "offline" ]]; then
                qemu-img convert -f qcow2 -O qcow2 -c "$target" "$backup_file" || { log "Error: qemu-img convert failed for $disk"; exit 1; }
            fi

            # Initialize or reset the chain file
            echo "$backup_file $(date +%s)" > "$BACKUP_CHAIN_FILE"

        else
            # Incremental backup
            local previous_backup=$(tail -n 1 "$BACKUP_CHAIN_FILE" | cut -d' ' -f1)
            local backup_file="$VM_BACKUP_DIR/$VM_NAME-${timestamp}_${disk}_inc.qcow2"
            log "Performing incremental backup for $disk (based on $previous_backup)..."

            if [[ "$BACKUP_TYPE" == "live" ]]; then
                # Live incremental backup using a snapshot
                local snapshot_file="$VM_BACKUP_DIR/$VM_NAME-${timestamp}_${disk}_snapshot.qcow2"

                # Create the incremental *snapshot* using qemu-img create -b
                qemu-img create -f qcow2 -b "$previous_backup" "$snapshot_file" || { log "Error creating incremental snapshot"; exit 1;}

                # Create the external snapshot in libvirt, pointing to the new file
                virsh snapshot-create-as --domain "$VM_NAME" --name "backup_snapshot_$disk" \
                  --description "Backup snapshot" --disk-only --atomic \
                  --diskspec "$disk,file=$snapshot_file" || { log "Error: Snapshot creation failed for $disk"; exit 1;}

                # Convert the *snapshot* to the final incremental backup file
                qemu-img convert -f qcow2 -O qcow2 "$snapshot_file" "$backup_file" || { log "Error: qemu-img convert failed for $disk"; exit 1; }

                # Delete the libvirt snapshot (and the temporary snapshot file)
                virsh snapshot-delete "$VM_NAME" "backup_snapshot_$disk" --diskspec "$disk" || { log "Warning: Snapshot deletion failed for $disk"; exit 1; }

            elif [[ "$BACKUP_TYPE" == "offline" ]]; then
                qemu-img create -f qcow2 -b "$previous_backup" "$backup_file" || { log "Error: qemu-img create failed for $disk"; exit 1; }
            fi

            # Append to the chain file
            echo "$backup_file $(date +%s)" >> "$BACKUP_CHAIN_FILE"
        fi

        # Verify the backup (both full and incremental)
        qemu-img check "$backup_file" || { log "Error: Backup image is corrupted ($disk)"; exit 1; }
    done <<< "$disks"

    log "$BACKUP_TYPE backup of $VM_NAME complete."
}

function restore_vm() {
    local VM_NAME="$1"

    log "Starting restore of $VM_NAME..."

    # Check if the VM is running and shut it down (with timeout)
    if virsh domstate "$VM_NAME" 2>/dev/null | grep -q running; then
        log "Stopping VM..."
        virsh shutdown "$VM_NAME" || { log "Warning: Shutdown command may have failed."; }
        local timeout=60
        local start_time=$(date +%s)

        while virsh domstate "$VM_NAME" 2>/dev/null | grep -q running; do
            sleep 1
            local elapsed_time=$(( $(date +%s) - start_time ))
            if [[ "$elapsed_time" -gt "$timeout" ]]; then
                log "Warning: VM failed to shut down gracefully.  Forcing power off."
                virsh destroy "$VM_NAME" || { log "Error: Failed to destroy VM"; exit 1; }
                break
            fi
        done
    fi

     #Get disks
    local disks=$(virsh domblklist "$VM_NAME" | awk '$1 ~ /^[hv]d[a-z]$/ || $1 ~ /^[s]d[a-z]$/ || $1 ~ /^nvme[0-9]n[0-9]$/ {print $1,$2}')

      # Check if disks were found
      if [ -z "$disks" ]; then
          log "Error: No disks found for VM $VM_NAME"
          exit 1
      fi

    # Loop through disks
    while read -r disk target; do
        local VM_BACKUP_DIR="$BACKUP_DIR/$VM_NAME"
        local BACKUP_CHAIN_FILE="$VM_BACKUP_DIR/${VM_NAME}_${disk}_chain.txt"

        # Check if the chain file exists
        if [[ ! -f "$BACKUP_CHAIN_FILE" ]]; then
            log "Error: No backup chain found for VM $VM_NAME disk $disk. Exiting."
            exit 1
        fi

        # Get the list of backups (full and incremental) - Not actually used, but good for debugging.
        local BACKUP_FILES=$(cat "$BACKUP_CHAIN_FILE" | cut -d' ' -f1)

        # Create a temporary file for the restored image
        local TEMP_RESTORED_IMAGE="$VM_BACKUP_DIR/${VM_NAME}_${disk}_restored_temp.qcow2"

        # "Flatten" the backup chain into a single image
        log "Flattening backup chain for $disk..."
        # Use qemu-img convert to combine the chain.  Get the *last* backup in the chain.
        qemu-img convert -f qcow2 -O qcow2 "$(tail -n 1 "$BACKUP_CHAIN_FILE" | cut -d' ' -f1)" "$TEMP_RESTORED_IMAGE" || { log "Error flattening backup chain"; exit 1; }

        # Restore the disk image
        log "Restoring disk image for $disk..."
        qemu-img convert -f qcow2 -O qcow2 "$TEMP_RESTORED_IMAGE" "$target" || { log "Error: qemu-img convert failed for $disk (restore)"; exit 1; }

        # Clean up the temporary file
        rm -f "$TEMP_RESTORED_IMAGE"
    done <<< "$disks"

    # Start the VM
    log "Starting VM..."
    virsh start "$VM_NAME" || { log "Error: Failed to start VM"; exit 1; }

    log "Restore of $VM_NAME complete."
}

function cleanup_backups() {
    log "Cleaning up old backups..."
    
    # First, verify and clean up chain files
    find "$BACKUP_DIR" -name "*_chain.txt" -type f -print0 | while IFS= read -r -d $'\0' chain_file; do
        local vm_name=$(basename "$(dirname "$chain_file")")
        local valid_chain=true
        local newest_backup=""
        local newest_timestamp=0

        # Verify chain integrity
        while read -r backup_file timestamp; do
            if [[ ! -f "$backup_file" ]]; then
                valid_chain=false
                break
            fi
            if (( timestamp > newest_timestamp )); then
                newest_timestamp=$timestamp
                newest_backup=$backup_file
            fi
        done < "$chain_file"

        if ! $valid_chain; then
            log "Warning: Invalid chain found in $chain_file - preserving newest backup"
            if [[ -n "$newest_backup" ]]; then
                echo "$newest_backup $newest_timestamp" > "$chain_file"
            else
                rm -f "$chain_file"
            fi
        fi
    done

    # Then clean up old backup folders
    find "$BACKUP_DIR" -mindepth 2 -maxdepth 2 -type d -name "[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]" | while read date_folder; do
        folder_date=$(basename "$date_folder")
        if ! folder_timestamp=$(date -d "${folder_date:0:2}/${folder_date:2:2}/${folder_date:4:4}" +%s 2>/dev/null); then
            log "Warning: Invalid date folder found: $date_folder"
            continue
        fi
        
        if (( folder_timestamp < $(date +%s) - (RETENTION_DAYS * 24 * 60 * 60) )); then
            # Check if any files in this folder are referenced in chain files
            if ! grep -q "$date_folder" "$BACKUP_DIR"/*/*_chain.txt 2>/dev/null; then
                log "Removing old backup folder: $date_folder"
                rm -rf "$date_folder"
            else
                log "Skipping folder with referenced backups: $date_folder"
            fi
        fi
    done

    # Clean up empty VM directories
    find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -empty -delete
}

# Add snapshot cleanup function
cleanup_snapshots() {
    local VM_NAME="$1"
    log "Cleaning up snapshots for $VM_NAME..."
    virsh snapshot-list "$VM_NAME" --name 2>/dev/null | while read -r snap; do
        virsh snapshot-delete "$VM_NAME" "$snap" --metadata 2>/dev/null
    done
}

# --- Main ---
rotate_log  # Rotate log file

if [[ "$1" == "backup" ]]; then
    check_lock  # Add lock check
    BACKUP_TYPE="$2"  # Get backup type FIRST
    VM_NAME="$3"      # Get VM name (might be empty)

    if [[ -z "$BACKUP_TYPE" ]]; then
        echo "Usage: $0 backup [live|offline] [<VM_NAME>]" >&3
        exit 1
    fi

    if [[ "$BACKUP_TYPE" != "live" && "$BACKUP_TYPE" != "offline" ]]; then
        echo "Error: Invalid backup type. Use 'live' or 'offline'." >&3
        exit 1
    fi

    if [[ -z "$VM_NAME" ]]; then
        # No VM name provided, back up all
        local VM_LIST  # Declare VM_LIST
        if [[ "$BACKUP_TYPE" == "live" ]]; then
            VM_LIST=$(virsh list --state-running --name)
        else
            VM_LIST=$(virsh list --all --name)
        fi

        if [[ -z "$VM_LIST" ]]; then
            log "No VMs found to backup."
            exit 0
        fi

        for VM_NAME in $VM_LIST; do
            backup_vm "$VM_NAME" "$BACKUP_TYPE"
        done
    else
        # VM name provided
        backup_vm "$VM_NAME" "$BACKUP_TYPE"
    fi

    cleanup_backups

elif [[ "$1" == "restore" ]]; then
    check_lock  # Add lock check
    if [[ -z "$2" ]]; then
        echo "Usage: $0 restore <VM_NAME>" >&3
        exit 1
    fi
    VM_NAME="$2"
    restore_vm "$VM_NAME"  # Fixed function call syntax - removed parentheses

else
    echo "Usage: $0 [backup|restore] [<VM_NAME>]" >&3
    echo "       $0 backup [live|offline] [<VM_NAME>]" >&3
    exit 1
fi

exit 0