#!/bin/bash

# --- Configuration ---
SNAPSHOT_NAME="backup_snapshot"
BACKUP_DIR="/path/to/backup/directory"  # Replace with your backup directory
RETENTION_DAYS=7 # Keep backups for 7 days

# --- Functions ---

function backup_vm() {
    VM_NAME="$1"

    echo "Starting backup of $VM_NAME..."

    # Check if the VM is running
    if ! virsh domstate "$VM_NAME" | grep -q running; then
        echo "VM is not running. Please start the VM before backup."
        exit 1
    fi

    # Get all disks and their targets
    disks=$(virsh domblklist "$VM_NAME" | awk '$1 ~ /^[hv]d[a-z]$/ || $1 ~ /^[s]d[a-z]$/ || $1 ~ /^nvme[0-9]n[0-9]p[0-9]$/ {print $1,$2}')

    # Check if disks were found
    if [ -z "$disks" ]; then
        echo "Error: No disks found for VM $VM_NAME"
        exit 1
    fi
    
    timestamp=$(date +%Y%m%d%H%M%S)
    snapshot_specs=""

    # Loop through the disks and build snapshot specifications
    while read -r disk target; do
        snapshot_file="$BACKUP_DIR/$VM_NAME-${timestamp}_${disk}_snapshot.qcow2"
        snapshot_specs+="--diskspec $disk,file=$snapshot_file "
    done <<< "$disks"

    # Create an external snapshot for all disks
    echo "Creating snapshot..."
    virsh snapshot-create-as --domain "$VM_NAME" --name "$SNAPSHOT_NAME" \
        --description "Backup snapshot" --disk-only --atomic --quiesce \
        $snapshot_specs || { echo "Error: Snapshot creation failed"; exit 1; }

    # Loop through disks again to create the final, compressed backups
     while read -r disk target; do
        snapshot_file="$BACKUP_DIR/$VM_NAME-${timestamp}_${disk}_snapshot.qcow2"
        backup_file="$BACKUP_DIR/$VM_NAME-${timestamp}_${disk}.qcow2"

        echo "Copying and compressing disk image ($disk)..."
        qemu-img convert -f qcow2 -O qcow2 -c "$snapshot_file" "$backup_file" || { echo "Error: qemu-img convert failed for $disk"; exit 1; }

        # Verify the backup
        echo "Verifying backup..."
        qemu-img check "$backup_file" || { echo "Error: Backup image is corrupted ($disk)"; exit 1; }
    done <<< "$disks"

    # Delete the snapshot
    echo "Deleting snapshot..."
    virsh snapshot-delete "$VM_NAME" "$SNAPSHOT_NAME" || { echo "Warning: Snapshot deletion failed"; }

    echo "Backup of $VM_NAME complete."
}
function restore_vm() {
    VM_NAME="$1"

    echo "Starting restore of $VM_NAME..."

    # Check if the VM is running and shut it down (with timeout)
    if virsh domstate "$VM_NAME" | grep -q running; then
        echo "Stopping VM..."
        virsh shutdown "$VM_NAME" || { echo "Warning: Shutdown command may have failed."; }
        timeout=60
        start_time=$(date +%s)

        while virsh domstate "$VM_NAME" | grep -q running; do
            sleep 1
            elapsed_time=$(( $(date +%s) - start_time ))
            if [ "$elapsed_time" -gt "$timeout" ]; then
                echo "Warning: VM failed to shut down gracefully.  Forcing power off."
                virsh destroy "$VM_NAME" || { echo "Error: Failed to destroy VM"; exit 1; }
                break
            fi
        done
    fi
    
    #Get disks
    disks=$(virsh domblklist "$VM_NAME" | awk '$1 ~ /^[hv]d[a-z]$/ || $1 ~ /^[s]d[a-z]$/ || $1 ~ /^nvme[0-9]n[0-9]p[0-9]$/ {print $1,$2}')

    # Check if disks were found
    if [ -z "$disks" ]; then
        echo "Error: No disks found for VM $VM_NAME"
        exit 1
    fi

    # Loop through the disks and restore
    while read -r disk target; do
        # Find the latest backup for this specific disk
        LATEST_BACKUP=$(find "$BACKUP_DIR" -name "$VM_NAME-*_${disk}.qcow2" -type f -print0 | sort -rz | xargs -0 head -n 1)

        if [ -z "$LATEST_BACKUP" ]; then
            echo "Error: No backup image found for disk $disk. Exiting."
            exit 1
        fi

        # Restore the disk image
        echo "Restoring disk image for $disk..."
        qemu-img convert -f qcow2 -O qcow2 "$LATEST_BACKUP" "$target" || { echo "Error: qemu-img convert failed for $disk"; exit 1; }
    done <<< "$disks"

    # Start the VM
    echo "Starting VM..."
    virsh start "$VM_NAME" || { echo "Error: Failed to start VM"; exit 1; }

    echo "Restore of $VM_NAME complete."
}

function cleanup_backups() {
    echo "Cleaning up old backups..."
    find "$BACKUP_DIR" -name "$VM_NAME-*.qcow2" -type f -mtime +"$RETENTION_DAYS" -delete
}

# --- Main ---

if [ "$1" == "backup" ]; then
    if [ -z "$2" ]; then
        echo "Usage: $0 backup <VM_NAME>"
        exit 1
    fi
    backup_vm "$2"
    cleanup_backups
elif [ "$1" == "restore" ]; then
    if [ -z "$2" ]; then
        echo "Usage: $0 restore <VM_NAME>"
        exit 1
    fi
    restore_vm "$2"
else
    echo "Usage: $0 [backup|restore] <VM_NAME>"
    exit 1
fi

exit 0