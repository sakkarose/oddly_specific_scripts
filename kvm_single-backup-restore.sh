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
    echo "VM is not running. Please start the VM before backup."
  fi
}

function restore_vm() {
  VM_NAME="$1"

  echo "Starting restore of $VM_NAME..."

  # Check if the VM is running
  if virsh domstate "$VM_NAME" | grep -q running; then
    echo "Stopping VM..."
    virsh shutdown "$VM_NAME"
    # Wait for VM to shutdown
    while virsh domstate "$VM_NAME" | grep -q running; do
      sleep 1
    done
  fi

  # Get the latest backup image
  LATEST_BACKUP=$(ls -t "$BACKUP_DIR/$VM_NAME-*.qcow2" | head -n 1)

  if [ -z "$LATEST_BACKUP" ]; then
    echo "No backup image found. Exiting."
    exit 1
  fi

  # Get disk information
  DISK_PATH=$(virsh domblklist "$VM_NAME" | awk '/vda/ {print $2}')

  # Replace the current disk image with the backup image
  echo "Restoring disk image..."
  cp "$LATEST_BACKUP" "$DISK_PATH"

  # Start the VM
  echo "Starting VM..."
  virsh start "$VM_NAME"
}

# --- Main ---

if [ "$1" == "backup" ]; then
  if [ -z "$2" ]; then
    echo "Usage: $0 backup <VM_NAME>"
    exit 1
  fi
  backup_vm "$2"
elif [ "$1" == "restore" ]; then
  if [ -z "$2" ]; then
    echo "Usage: $0 restore <VM_NAME>"
    exit 1
  fi
  restore_vm "$2"
else
  echo "Usage: $0 [backup|restore] <VM_NAME>"
fi
