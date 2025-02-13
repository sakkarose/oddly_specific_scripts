#!/bin/bash

# Configuration
BACKUP_DIR="/path/to/backup/directory" # Change this to your backup location
FULL_BACKUP retention in days
RETENTION_DAYS=7      # Number of daily backups to keep
RETENTION_WEEKS=4     # Number of weekly full backups to keep

# Directories
FULL_BACKUP_DIR="$BACKUP_DIR/full"
INCR_BACKUP_DIR="$BACKUP_DIR/incr"

# Get all offline domains
function get_offline_domains {
    virsh list --all | tail -n +3 | awk '{print $2}' | 
    while read DOMAIN; do
        virsh domstate $DOMAIN | grep -q stopped && echo $DOMAIN
    done
}

# Get disk images for a domain
function get_domain_disks {
    virsh domblklist $1 | tail -n +3 | awk '{print $3}' | 
    while read DISK; do
        echo $DISK
    done
}

# Perform backup for a disk
function perform_backup {
    local DOMAIN=$1
    local DISK=$2
    local BACKUP_TYPE=$3
    local TIMESTAMP=$(date +%Y%m%d%H%M%S)

    # Create backup directory structure
    local BACKUP_PATH="$BACKUP_DIR/${DOMAIN}/${BACKUP_TYPE}/${DISK}"
    mkdir -p $BACKUP_PATH

    # Generate backup filename
    local BACKUP_FILE="$BACKUP_PATH/${TIMESTAMP}.img"

    echo "Backing up $DOMAIN ($DISK) - $BACKUP_TYPE backup to $BACKUP_FILE"

    # Perform the backup
    if [[ $BACKUP_TYPE == "full" ]]; then
        qemu-img convert -p -O qcow2 $DISK $BACKUP_FILE
    else
        # Incremental backup
        local LAST_FULL_BACKUP=$(ls -t $FULL_BACKUP_DIR/$DOMAIN/$DISK | head -n1)
        if [ -z "$LAST_FULL_BACKUP" ]; then
            echo "Error: No full backup found for incremental backup" >&2
            exit 1
        fi
        qemu-img convert -p -O qcow2 -incremental $DISK $BACKUP_FILE
    fi

    # Set the last backup time
    touch $BACKUP_FILE
}

# Main script
echo "Starting backup process at $(date)"

# Get list of offline domains
OFFLINE_DOMAINS=$(get_offline_domains)

if [ -z "$OFFLINE_DOMAINS" ]; then
    echo "No offline domains found. Backup process completed."
    exit 0
fi

for DOMAIN in $OFFLINE_DOMAINS; do
    echo "Backing up domain: $DOMAIN"

    # Get list of disks for the domain
    DISKS=$(get_domain_disks $DOMAIN)
    if [ -z "$DISKS" ]; then
        echo "No disks found for domain $DOMAIN. Skipping."
        continue
    fi

    # Check if full backup is needed (every 7 days)
    LAST_FULL=$(ls -t $FULL_BACKUP_DIR/$DOMAIN/{DISK} | head -n1)
    if [ -z "$LAST_FULL" ] || [ $(($(date +%s) - $(date +%s -r $LAST_FULL)) / 86400) -ge 7 ]; then
        BACKUP_TYPE="full"
    else
        BACKUP_TYPE="incremental"
    fi

    for DISK in $DISKS; do
        echo "Processing disk: $DISK"
        perform_backup $DOMAIN $DISK $BACKUP_TYPE
    done

    # Apply retention policy
    echo "Applying retention policy for domain: $DOMAIN"

    # Keep last RETENTION_DAYS daily backups
    find $INCR_BACKUP_DIR/$DOMAIN -type f -printf "%T@ %p\n" | 
    sort -n | 
    awk -v keep=$RETENTION_DAYS '{ if (count++ >= keep) print $2 }' | 
    xargs -r rm

    # Keep last RETENTION_WEEKS weekly full backups
    find $FULL_BACKUP_DIR/$DOMAIN -type f -printf "%T@ %p\n" | 
    sort -n | 
    awk -v keep=$RETENTION_WEEKS '{ if (count++ >= keep) print $2 }' | 
    xargs -r rm
done

echo "Backup process completed at $(date)"