#!/bin/bash

ROOT_DIR='/home/backup-str'
LOG_DIR="$ROOT_DIR/log"
UPTIME_KUMA_URL='https://uptime.mizu.reisen/api/push/Y80kVEn7Os' 

get_week_number() {
    local date="$1"
    local week_number=$(date +%V --date="$date -$(date +%d -d "$date") days +1 day")
    echo $(( (week_number - 1) % 4 + 1 ))
}

DATE=$(date +%Y-%m-%d)
WEEK_NUMBER=$(get_week_number "$DATE")

DOMAINS=$(virsh list --all --name)

for DOMAIN in $DOMAINS; do
    DESTINATION_DIR="$ROOT_DIR/$DOMAIN/$(date +%Y)/$(date +%m)/$WEEK_NUMBER"

    # Create dest dir if it doesn't exist
    if [ ! -d "$DESTINATION_DIR" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Creating directory for domain: $DOMAIN" >> "$LOG_DIR/$DOMAIN.log" 
        mkdir -p "$DESTINATION_DIR"
    fi

    # Dump backup info if dir is empty
    if [ "$(ls -A $DESTINATION_DIR)" ]; then 
        virtnbdrestore -i "$DESTINATION_DIR" -o dump 2>&1 | tee -a "$LOG_DIR/$DOMAIN.log"
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Skipping 'virtnbdrestore -o dump' for $DOMAIN as the directory is empty." >> "$LOG_DIR/$DOMAIN.log"
    fi

    # Backup
    output=$(virtnbdbackup -d "$DOMAIN" -l auto -o "$DESTINATION_DIR/" 2>&1) 
    echo "$output" | tee -a "$LOG_DIR/$DOMAIN.log"

    # Uptime Kuma backup notification
    if echo "$output" | grep -q "Error during backup"; then
        curl -fsS -m 10 --retry 5 -o /dev/null "$UPTIME_KUMA_URL?status=down&msg=Backup%20of%20$DOMAIN%20failed"
    else
        curl -fsS -m 10 --retry 5 -o /dev/null "$UPTIME_KUMA_URL?status=up&msg=Backup%20of%20$DOMAIN%20successful"
    fi

    # Verify the backup
    verify_output=$(virtnbdrestore -i "$DESTINATION_DIR" -o verify 2>&1)
    echo "$verify_output" | tee -a "$LOG_DIR/$DOMAIN.log"

    # Failed verification = Status Down
    if echo "$verify_output" | grep -q "Stored sums do not match"; then
        curl -fsS -m 10 --retry 5 -o /dev/null "$UPTIME_KUMA_URL?status=down&msg=Verification%20of%20$DOMAIN%20backup%20failed" 
    fi 
done
