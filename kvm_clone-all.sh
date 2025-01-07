#!/bin/bash

# Get a list of all domains
domains=$(virsh list --all --name)

# Loop through each domain
for domain in $domains; do
  echo "Cloning domain: $domain"

  # Get the current date and time for the snapshot name
  snapshot_name=$(date +%Y%m%d%H%M%S)

  # Create a snapshot of the domain
  virsh snapshot-create-as $domain "$snapshot_name" \
    --description "Snapshot before cloning" \
    --atomic --quiesce

  if [[ $? -ne 0 ]]; then
    echo "Error creating snapshot for domain: $domain"
    continue
  fi

  # Get the XML configuration of the domain
  virsh dumpxml $domain > /tmp/$domain.xml

  # Generate a new UUID for the cloned domain
  new_uuid=$(uuidgen)

  # Replace the old UUID with the new one in the XML configuration
  sed -i "s/<uuid>.*<\/uuid>/<uuid>$new_uuid<\/uuid>/g" /tmp/$domain.xml

  # Replace the domain name in the XML configuration
  new_domain_name="${domain}-clone-$snapshot_name"
  sed -i "s/<name>.*<\/name>/<name>$new_domain_name<\/name>/g" /tmp/$domain.xml

  # Remove MAC addresses from the XML configuration
  sed -i '/mac address/d' /tmp/$domain.xml

  # Define the new domain
  virsh define /tmp/$domain.xml

  if [[ $? -ne 0 ]]; then
    echo "Error defining cloned domain: $new_domain_name"
    continue
  fi

  # Start the cloned domain
  virsh start $new_domain_name

  if [[ $? -ne 0 ]]; then
    echo "Error starting cloned domain: $new_domain_name"
    continue
  fi

  echo "Domain cloned successfully: $new_domain_name"

done
