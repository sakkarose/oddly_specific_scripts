#!/bin/bash

# Cloudflare API details
CLOUDFLARE_API_TOKEN=""
CLOUDFLARE_ZONE_ID=""
RECORDS_TO_UPDATE="sub.domain.com sub1.domain.com"

# Uptime Kuma notification URL without any query parameters.
UPTIME_KUMA_PUSH_URL=""

set -e

# Function to send a failure notification to Uptime Kuma and exit.
send_failure_notification() {
    record_name="$1"
    error_message="$2"
    echo "ERROR for $record_name: $error_message"
    # Reverted to using a GET request with query parameters for better compatibility.
    # The message is URL-encoded to handle special characters correctly.
    curl -s -k -X GET "${UPTIME_KUMA_PUSH_URL}?status=down&msg=$(echo "Cloudflare DDNS update failed: ${error_message}" | sed -e 's/ /%20/g')" > /dev/null
    exit 1
}

# Get the current public IPv4 address once at the beginning of the script.
# We explicitly use an IPv4-only service to prevent issues with IPv6.
CURRENT_IP=$(curl -s https://ipv4.icanhazip.com)
if [ -z "$CURRENT_IP" ]; then
    send_failure_notification "Global" "Failed to get current public IP address."
fi
echo "Current public IP is: $CURRENT_IP"

# A flag to track if any IP was updated.
IP_CHANGE_DETECTED=0
IP_UPDATE_FAILED=0

# Loop through each record in the list and update if necessary.
for RECORD_NAME in $RECORDS_TO_UPDATE; do
    echo "Processing record: $RECORD_NAME"

    # Get the current DNS record details from Cloudflare using the record name.
    # We now use standard shell tools (grep and cut) to parse the JSON.
    DNS_RECORD_JSON=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?name=$RECORD_NAME" \
         -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
         -H "Content-Type: application/json")

    # Check for Cloudflare API errors by searching for '"success":false'.
    if echo "$DNS_RECORD_JSON" | grep -q '"success":false'; then
        # Parse the error message using standard shell tools.
        ERROR_MSG=$(echo "$DNS_RECORD_JSON" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
        send_failure_notification "$RECORD_NAME" "Cloudflare API Error: $ERROR_MSG"
    fi

    # Parse the DNS record ID from the JSON response.
    DNS_RECORD_ID=$(echo "$DNS_RECORD_JSON" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    # Parse the DNS IP from the JSON response.
    DNS_IP=$(echo "$DNS_RECORD_JSON" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -z "$DNS_RECORD_ID" ] || [ -z "$DNS_IP" ]; then
        send_failure_notification "$RECORD_NAME" "Failed to find or parse DNS record details for '$RECORD_NAME'."
    fi
    echo "Current DNS record IP for $RECORD_NAME is: $DNS_IP"

    # Compare the IPs
    if [ "$CURRENT_IP" = "$DNS_IP" ]; then
        echo "IP addresses match. No update needed for $RECORD_NAME."
    else
        echo "IP addresses differ. Updating Cloudflare DNS record for $RECORD_NAME."
        IP_CHANGE_DETECTED=1

        # Update the Cloudflare DNS record.
        UPDATE_RESPONSE=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$DNS_RECORD_ID" \
             -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
             -H "Content-Type: application/json" \
             --data "{\"type\":\"A\",\"name\":\"$RECORD_NAME\",\"content\":\"$CURRENT_IP\",\"ttl\":1,\"proxied\":false}")

        # Check if the update was successful.
        if echo "$UPDATE_RESPONSE" | grep -q '"success":false'; then
            # Parse the error message using standard shell tools.
            ERROR_MSG=$(echo "$UPDATE_RESPONSE" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
            echo "Error updating record for $RECORD_NAME: $ERROR_MSG"
            IP_UPDATE_FAILED=1
        else
            echo "Cloudflare DDNS record for $RECORD_NAME updated successfully to $CURRENT_IP."
            # Send a success notification to Uptime Kuma.
            # Reverted to using a GET request with query parameters for better compatibility.
            curl -s -k -X GET "${UPTIME_KUMA_PUSH_URL}?status=up&msg=$(echo "IP changed to: ${CURRENT_IP}" | sed -e 's/ /%20/g')" > /dev/null
        fi
    fi
done

# Send a single notification to Uptime Kuma based on the final outcome.
if [ "$IP_UPDATE_FAILED" -eq 1 ]; then
    curl -s -k -X GET "${UPTIME_KUMA_PUSH_URL}?status=down&msg=$(echo "One or more IP updates failed." | sed -e 's/ /%20/g')" > /dev/null
elif [ "$IP_CHANGE_DETECTED" -eq 1 ]; then
    curl -s -k -X GET "${UPTIME_KUMA_PUSH_URL}?status=up&msg=$(echo "IP changed to: ${CURRENT_IP}" | sed -e 's/ /%20/g')" > /dev/null
else
    curl -s -k -X GET "${UPTIME_KUMA_PUSH_URL}?status=up&msg=$(echo "IP is the same: ${CURRENT_IP}" | sed -e 's/ /%20/g')" > /dev/null
fi
