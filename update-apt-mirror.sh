#!/bin/bash

# Backup the original sources.list file
sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak

# Get available mirrors, excluding duplicates and sorting
mirrors=$(sudo apt-get update -o Dir::Etc::sourcelist="sources.list.d/official-package-repositories.list" \
    -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" 2>&1 | grep ^deb | cut -d' ' -f2 | sort -u)

# File to store test results
test_results="/tmp/mirror_speed_test.txt"
rm -f "$test_results"  # Clear any existing results

# Test each mirror
for mirror in $mirrors; do
    # Redirect all output to test_results
    {
        echo "Testing $mirror"
        sudo apt-get update -o Dir::Etc::sourcelist="/etc/apt/sources.list.d/mirror-test.list" \
            -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" &> /dev/null &&
        # Limit `time` to only output real time, and measure only curl 
        /usr/bin/time -f "%e" curl -o /dev/null -s "$mirror/dists/$(lsb_release -sc)/main/binary-amd64/Packages.gz"
    } >> "$test_results" 2>&1
done

# Sort results, filter out errors, and select the fastest mirror
fastest_mirror=$(sort -nk2 "$test_results" | head -n 1 | cut -d' ' -f1) 
echo "Fastest mirror: $fastest_mirror"

# Create a temporary file with the fastest mirror settings
echo "deb $fastest_mirror $(lsb_release -sc) main restricted universe multiverse" > /etc/apt/sources.list

# Update the system's package list
sudo apt-get update
