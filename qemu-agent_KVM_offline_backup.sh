#!/bin/bash

# Configuration
BACKUP_DIR="/path/to/backup"  # Replace with your backup directory
DOMAIN_NAMES=("domain1" "domain2") # Array of domain names to backup
FULL_BACKUP_INTERVAL="7"  # Days between full backups
RETENTION_DAYS="30"       # Number of days to keep backups

# Function to perform a full backup
full_backup() {
  domain="$1"
  echo "Performing full backup for $domain..."

  virsh shutdown "$domain"
  if [[ $? -ne 0 ]]; then
    echo "Error shutting down $domain. Skipping."
    return 1
  fi

  FULL_BACKUP_FILE="$BACKUP_DIR/full/${domain}.qcow2"
  # Check if the domain disk exists
  DISK_IMAGE="/var/lib/libvirt/images/${domain}.qcow2"
  if [[ ! -f "$DISK_IMAGE" ]]; then
      echo "Error: Disk image $DISK_IMAGE not found for $domain"
      virsh start "$domain"
      return 1
  fi

  # Efficient full backup with cp if qcow2 source, otherwise convert
  if [[ $(qemu-img info "$DISK_IMAGE" | grep "file format:" | awk '{print $3}') == "qcow2" ]]; then
      cp "$DISK_IMAGE" "$FULL_BACKUP_FILE"
  else
      qemu-img convert -f qcow2 -O qcow2 "$DISK_IMAGE" "$FULL_BACKUP_FILE"
  fi


  virsh start "$domain"
  if [[ $? -ne 0 ]]; then
    echo "Error starting $domain after backup."
  fi

  echo "Full backup for $domain complete."
}

# Function to perform an incremental backup
incremental_backup() {
  domain="$1"
  echo "Performing incremental backup for $domain..."

  virsh shutdown "$domain"
  if [[ $? -ne 0 ]]; then
    echo "Error shutting down $domain. Skipping."
    return 1
  fi

  FULL_BACKUP_FILE="$BACKUP_DIR/full/${domain}.qcow2"
  LATEST_INCREMENTAL=$(ls -rt "$BACKUP_DIR/incremental/${domain}" | tail -n 1)

  if [[ -z "$LATEST_INCREMENTAL" ]]; then
    echo "No previous incremental backup found. Creating a new full backup as base for incremental."
    full_backup "$domain"
    LATEST_INCREMENTAL="$BACKUP_DIR/full/${domain}.qcow2" # Use full backup as base
  else
    LATEST_INCREMENTAL="$BACKUP_DIR/incremental/${domain}/$LATEST_INCREMENTAL"
  fi

  DISK_IMAGE="/var/lib/libvirt/images/${domain}.qcow2"
    if [[ ! -f "$DISK_IMAGE" ]]; then
        echo "Error: Disk image $DISK_IMAGE not found for $domain"
        virsh start "$domain"
        return 1
    fi
  INCREMENTAL_BACKUP_FILE="$BACKUP_DIR/incremental/${domain}/${domain}_$(date +%Y%m%d%H%M%S).qcow2"
  ORIGINAL_SIZE=$(qemu-img info "$DISK_IMAGE" | grep "virtual size:" | awk '{print $3}')
  qemu-img create -f qcow2 -b "$LATEST_INCREMENTAL" "$INCREMENTAL_BACKUP_FILE" "$ORIGINAL_SIZE"

  virsh start "$domain"
  if [[ $? -ne 0 ]]; then
    echo "Error starting $domain after backup."
  fi

  echo "Incremental backup for $domain complete."
}

# Function to clean up old backups
cleanup_backups() {
  echo "Cleaning up old backups..."
  find "$BACKUP_DIR/full" -type f -mtime +$RETENTION_DAYS -delete
  find "$BACKUP_DIR/incremental" -type f -mtime +$RETENTION_DAYS -delete
  echo "Cleanup complete."
}


# Main script logic
for domain in "${DOMAIN_NAMES[@]}"; do
  FULL_BACKUP_DATE_FILE="$BACKUP_DIR/full/.last_full_backup_${domain}"

  if [[ ! -f "$FULL_BACKUP_DATE_FILE" || $(date -d "$(cat "$FULL_BACKUP_DATE_FILE")" +%s) -lt $(date -d "-$FULL_BACKUP_INTERVAL days" +%s) ]]; then
    full_backup "$domain"
    date +%Y-%m-%d > "$FULL_BACKUP_DATE_FILE"
  else
    incremental_backup "$domain"
  fi
done

cleanup_backups

echo "Backup process complete."