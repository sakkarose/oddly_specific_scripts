#!/bin/bash

DESTINATION_DIR="/home/kvm-backup"
LOG_FILE="/path/to/your/clone_vm.log"
exec &> "$LOG_FILE"  # Redirect all output to the log file

function cleanup {
    if [ "$STATE" == "running" ]; then
        echo "  Resuming original domain..."
        virsh resume "$DOMAIN"
        if [ $? -ne 0 ]; then
            echo "Error resuming domain '$DOMAIN'."
        fi
    fi
    exit 1
}

trap cleanup SIGINT SIGTERM

if [ ! -d "$DESTINATION_DIR" ]; then
    echo "Error: Destination directory '$DESTINATION_DIR' does not exist."
    exit 1
fi

DOMAINS=$(virsh list --all --name)

for DOMAIN in $DOMAINS; do
    echo "Cloning domain '$DOMAIN'..."

    DISK_SIZE=$(virsh domblklist "$DOMAIN" | grep vd | awk '{print $3}' | xargs -I {} qemu-img info {} | grep 'virtual size' | awk '{print $3}')
    DISK_SIZE_GB=$(echo "scale=2; $DISK_SIZE / 1024 / 1024 / 1024" | bc)
    AVAILABLE_SPACE=$(df -h "$DESTINATION_DIR" | awk 'NR==2{print $4}' | sed 's/[GMK]//') 
    UNIT=$(df -h "$DESTINATION_DIR" | awk 'NR==2{print $4}' | sed 's/[0-9]*//')

    # Convert to GB based on unit
    if [ "$UNIT" == "G" ]; then
        AVAILABLE_SPACE_GB=$AVAILABLE_SPACE
    elif [ "$UNIT" == "M" ]; then
        AVAILABLE_SPACE_GB=$(echo "scale=2; $AVAILABLE_SPACE / 1024" | bc)
    elif [ "$UNIT" == "K" ]; then
        AVAILABLE_SPACE_GB=$(echo "scale=2; $AVAILABLE_SPACE / 1024 / 1024" | bc)
    else
        echo "Error: Unrecognized unit in disk space output."
        exit 1
    fi

    # Check if there is enough space
    if (( $(echo "$AVAILABLE_SPACE_GB < $DISK_SIZE_GB" | bc -l) )); then
        echo "Error: Not enough space in '$DESTINATION_DIR' to clone '$DOMAIN' (needs $DISK_SIZE_GB GB)."
        continue  # Skip to the next domain
    fi

    STATE=$(virsh domstate "$DOMAIN")

    if [ "$STATE" == "running" ]; then
        echo "  Domain is running, suspending..."
        virsh suspend "$DOMAIN"
        if [ $? -ne 0 ]; then
            echo "Error suspending domain '$DOMAIN'."
            cleanup
            exit 1 
        fi
    fi

    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    CLONE_NAME="$DOMAIN-clone-$TIMESTAMP" 
    virt-clone --original "$DOMAIN" --name "$CLONE_NAME" --auto-clone --file "$DESTINATION_DIR/$CLONE_NAME.qcow2"

    if [ $? -eq 0 ]; then
        echo "  Domain '$DOMAIN' cloned successfully to '$DESTINATION_DIR/$CLONE_NAME.qcow2'."

        # --- Retention Policy (Keep last 3 clones) ---
        # Get a list of clones for the current domain, sorted by modification time (oldest first)
        CLONES=$(find "$DESTINATION_DIR" -name "$DOMAIN-clone-*" -type f -printf "%T@ %p\n" | sort -n | awk '{print $2}')

        # Delete clones older than the last 3
        while [ $(echo "$CLONES" | wc -l) -gt 3 ]; do
            OLDEST_CLONE=$(echo "$CLONES" | head -n 1)
            echo "  Deleting old clone: $OLDEST_CLONE"
            rm -f "$OLDEST_CLONE"
            CLONES=$(echo "$CLONES" | tail -n +2)  # Remove the oldest clone from the list
        done

    else
        echo "  Error cloning domain '$DOMAIN'."
        cleanup
    fi

    if [ "$STATE" == "running" ]; then
        echo "  Resuming domain..."
        virsh resume "$DOMAIN"
        if [ $? -ne 0 ]; then
            echo "Error resuming domain '$DOMAIN'."
        fi
    fi
done

echo "Cloning complete."
