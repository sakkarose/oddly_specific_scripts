#!/bin/bash

# --- Configuration ---
ROOT_DIR='/home/backup-str'
LOG_DIR="$ROOT_DIR/log"
UPTIME_KUMA_URL='uptime-kuma-link'
RETENTION_PERIOD=4  # In weeks
COPY_TO_NETWORK="true"
RCLONE_REMOTE="kvm-network-backupcopy"
RCLONE_REMOTE_DIR="/home/hoangdt/kvm-backupcopy"


# Get the week number of the month (1-4)
get_week_number() {
    local date="$1"
    local week_number=$(date +%V --date="$date -$(date +%d -d "$date") days +1 day")
    echo $(( (week_number - 1) % 4 + 1 ))
}

DATE=$(date +%Y-%m-%d)
WEEK_NUMBER=$(get_week_number "$DATE")

LOG_FILE="$LOG_DIR/backup_$(date +%Y-%m).log"

# Rotate log file at the beginning of each month
if [ $(date +%d) -eq "01" ]; then
    mv "$LOG_FILE" "$LOG_FILE.$(date +%Y%m%d%H%M%S)"
    touch "$LOG_FILE"
fi

DOMAINS=$(virsh list --all --name)

for DOMAIN in $DOMAINS; do
    DESTINATION_DIR="$ROOT_DIR/$DOMAIN/$(date +%Y)/$(date +%m)/$WEEK_NUMBER" 

    # Create dest dir if it doesn't exist
    if [ ! -d "$DESTINATION_DIR" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Creating directory for domain: $DOMAIN" >> "$LOG_FILE" 
        mkdir -p "$DESTINATION_DIR"
    fi

    # Dump backup information if dir is empty
    if [ "$(ls -A $DESTINATION_DIR)" ]; then 
        virtnbdrestore -i "$DESTINATION_DIR" -o dump 2>&1 | tee -a "$LOG_FILE"
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Skipping 'virtnbdrestore -o dump' for $DOMAIN as the directory is empty." >> "$LOG_FILE"
    fi

    # Backup
    output=$(virtnbdbackup -d "$DOMAIN" -l auto -o "$DESTINATION_DIR/" 2>&1) 
    echo "$output" | tee -a "$LOG_FILE"

    # Send notification for backup status
    if echo "$output" | grep -q "Error during backup"; then
        curl -fsS -m 10 --retry 5 -o /dev/null "$UPTIME_KUMA_URL?status=down&msg=Backup%20of%20$DOMAIN%20failed"
    else
        curl -fsS -m 10 --retry 5 -o /dev/null "$UPTIME_KUMA_URL?status=up&msg=Backup%20of%20$DOMAIN%20successful"
    fi

    # Verify
    verify_output=$(virtnbdrestore -i "$DESTINATION_DIR" -o verify 2>&1)
    echo "$verify_output" | tee -a "$LOG_FILE"

    # Send notification for verification status (only on failure)
    if echo "$verify_output" | grep -q "Stored sums do not match"; then
        curl -fsS -m 10 --retry 5 -o /dev/null "$UPTIME_KUMA_URL?status=down&msg=Verification%20of%20$DOMAIN%20backup%20failed" 
    fi

    # Calculate the cutoff week number
    current_week=$(date +%V)
    cutoff_week=$(( current_week - RETENTION_PERIOD ))

    # Cleanup old backup directories (older than the cutoff week)
    find "$ROOT_DIR/$DOMAIN" -mindepth 1 -type d -mtime +$((RETENTION_PERIOD * 7)) -print0 | while IFS= read -r -d '' dir; do
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Removing old backup directory: $dir" >> "$LOG_FILE"
        rm -rf "$dir"
    done
done

# Sync with network storage using rclone sync
if [ "$COPY_TO_NETWORK" = "true" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Syncing with network storage..." >> "$LOG_FILE"
    rclone sync -v --retries 5 "$ROOT_DIR" "$RCLONE_REMOTE:$RCLONE_REMOTE_DIR" >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Successfully synced with network storage." >> "$LOG_FILE"
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Error syncing with network storage." >> "$LOG_FILE"
        curl -fsS -m 10 --retry 5 -o /dev/null "$UPTIME_KUMA_URL?status=down&msg=Sync%20with%20network%20storage%20failed"
    fi
fi
