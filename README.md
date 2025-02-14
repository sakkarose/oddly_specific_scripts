# oddly_specific_scripts
Personal scripts that I created for my unnecessary personal uses

**Scripts List**

* **Offline_WU.ps1** - (**PowerShell**): Installs all offline Windows updates (.msu files) found in its own directory, ensuring it runs with administrator privileges. Error handling is not necessary since it won't take long before wusa knows this update is already installed or not elligible.
* **Microsoft-Edge_removal.ps1** - (**PowerShell**): This script thoroughly removes Microsoft Edge from Windows systems, including uninstalling all packages, deleting files and folders, clearing registry entries, and disabling scheduled tasks.
* **update-apt-mirror.sh** - (**Shell**): This script fetches, tests and updates the sources.list for OS that uses apt as package manager.
* **BLE-deauth.py** - (**Python**): A simple single-address BLE deauth using bleak.
* **everySingleImage.pl** - (**Squid**): A script that replaces every image (maybe) on a website.
* **rewriteURL.pl** - (**Squid**): A script that replaces the url with a preset one.
* **nessus_trial_reset.py** - (**Python**): A script to do an update on both trial and database. Credit to [Harsh Dhamaniya](https://github.com/harshdhamaniya/nessuskeygen) for their POST request to get a new trial code.
* **subfolder_index.ps1** - (**PowerShell**): This script will sort, print and write only the subfolders (level 3) of every subfolders (level 2) in the current directory.
* **virtnbdbackup-alldomain.sh** - (**Shell**): Using virtnbdbackup to backup (full/incremental) all domains of the host. Additionally, it will dump backup info and verify the backup. If there is any problem with backup job or verification, it will send a notification to Uptime Kuma.
* **MACchanger.ps1** - (**PowerShell**): Select and change MAC address randomly or with a value.
* **qemu-agent_KVM_backup.sh** & **agentless_KVM_backup.sh**: WIP - KVM native backup with and without qemu-agent.

