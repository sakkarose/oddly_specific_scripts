#!/bin/bash

# --- Configuration ---
SNAPSHOT_NAME="backup_snapshot"
BACKUP_DIR="/path/to/backup/directory"  # Replace with your backup directory

# --- Functions ---

function backup_vm() {
  VM_NAME="$1"

  echo "Starting backup of $VM_NAME..."

  # Check if the VM is running
  if virsh domstate "$VM_NAME" | grep -q running; then
    # Create a snapshot
    echo "Creating snapshot..."
    virsh snapshot-create-as "$VM_NAME" "$SNAPSHOT_NAME" \
      --description "Backup snapshot" --atomic --quiesce

    # Get disk information
    DISK_PATH=$(virsh domblklist "$VM_NAME" | awk '/vda/ {print $2}')

    # Copy the disk image to the backup directory
    echo "Copying disk image..."
    cp "$DISK_PATH" "$BACKUP_DIR/$VM_NAME-$(date +%Y%m%d%H%M%S).qcow2"

    # Delete the snapshot
    echo "Deleting snapshot..."
    virsh snapshot-delete "$VM_NAME" "$SNAPSHOT_NAME" --metadata

  else
    echo "VM is not running. Skipping backup."
  fi
}

# --- Main ---

# Get a list of all VMs
VM_LIST=$(virsh list --all --name)

# Loop through each VM
for VM_NAME in $VM_LIST; do
  backup_vm "$VM_NAME"
done

echo "Backup complete!"
