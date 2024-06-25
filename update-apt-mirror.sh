#!/bin/bash

# Backup the original sources.list file
sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak

# Get a list of available mirrors from official repositories
mirrors=$(sudo apt-get update -o Dir::Etc::sourcelist="sources.list.d/official-package-repositories.list" \
    -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" 2>&1 | grep ^deb | awk '{print $2}' | sort -u)

# File to store test results
test_results="/tmp/mirror_speed_test.txt"

# Test each mirror's download speed and status
for mirror in $mirrors; do
    echo "deb $mirror $(lsb_release -sc) main restricted universe multiverse" > /etc/apt/sources.list.d/mirror-test.list
    if sudo apt-get update -o Dir::Etc::sourcelist="sources.list.d/mirror-test.list" \
       -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" &> /dev/null; then
        if ! time curl -o /dev/null -s -w "%{time_total}\n" "$mirror/dists/$(lsb_release -sc)/main/binary-amd64/Packages.gz" >> "$test_results" 2>/dev/null; then
            echo "Error testing $mirror" >> "$test_results"
        fi
    else
        echo "Error updating from $mirror" >> "$test_results"
    fi
done

# Sort results, filter out errors, and select the fastest mirror
fastest_mirror=$(sort -n "$test_results" | grep -E '^[0-9]+\.[0-9]+$' | head -n 1 | awk '{print $2}')

# Update sources.list with the fastest mirror
sudo sed -i "s|http://[^ ]*|$fastest_mirror|g" /etc/apt/sources.list

echo "Updated sources.list with fastest mirror: $fastest_mirror"

# Clean up temporary files
rm -f "$test_results" /etc/apt/sources.list.d/mirror-test.list
