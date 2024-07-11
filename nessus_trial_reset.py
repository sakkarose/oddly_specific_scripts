#!/usr/bin/env python3

import subprocess
import ctypes
import sys
import os
import random
import string
import requests
import re

def get_mail():
    S = 15
    D = 7
    E = [".com", ".in", ".co", ".cn", ".org", ".info", ".eu", ".ru", ".de", ".net"]
    name = ''.join(random.choices(string.ascii_uppercase + string.digits, k=S))
    domain = ''.join(random.choices(string.ascii_uppercase + string.digits, k=S))
    extension = E[random.randint(0, 9)]
    mail_id = name + "@" + domain + extension
    return mail_id

def generate_nessus_pro():
    data = {
        "first_name": "cheems",
        "last_name": "Singh",
        "email": get_mail(),
        "phone": random.randrange(0000000000, 9999999999, 10),
        "code": "",
        "country": "IN",
        "region": "",
        "zip": "505474",
        "title": "security engineer",
        "company": "secyrask",
        "consentOptIn": "true",
        "essentialsOptIn": "false",
        "pid": "",
        "utm_source": "",
        "utm_campaign": "",
        "utm_medium": "",
        "utm_content": "",
        "utm_promoter": "",
        "utm_term": "",
        "alert_email": "",
        "_mkto_trk": "id:934-XQB-568&token:_mch-tenable.com-1667551532394-27662",
        "mkt_tok": "",
        "queryParameters": "utm_promoter=&utm_source=&utm_medium=&utm_campaign=&utm_content=&utm_term=&pid=&lookbook=&product_eval=nessus",
        "referrer": "https://www.tenable.com/products/nessus/nessus-professional?utm_promoter=&utm_source=&utm_medium=&utm_campaign=&utm_content=&utm_term=&pid=&lookbook=&product_eval=nessus",
        "lookbook": "",
        "apps": ["nessus"],
        "companySize": "10-49",
        "preferredSiteId": "",
        "tempProductInterest": "Nessus Professional",
        "partnerId": ""
    }

    response = requests.post('https://www.tenable.com/evaluations/api/v1/nessus-pro', json=data)
    try:
        regex = r"\"code\":\"(.*)\","
        matches = re.search(regex, response.text)
        activation_code = matches.group(1)
        print("Nessus Activation Code: " + activation_code)
        return activation_code
    except AttributeError:
        print("Failed to retrieve Nessus Activation Code.")
        return None

def run_cmd(command):
    """Executes a command and waits for it to finish, printing output and error if any."""
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    print(f"\nCommand:\n{command}")
    if result.stdout:  # Check if there's any standard output
        return result.stdout.strip()  
    else:
        return None

def is_admin():
    """Checks if the script is running with administrator privileges."""
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except:
        return False

def run_as_admin():
    """Relaunches the script with administrator privileges."""
    ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, " ".join(sys.argv), None, 1)


def write_plugin_info(version):
    nessus_dir = r"C:\ProgramData\Tenable\Nessus"  # Define Nessus directory
    file_path = os.path.join(nessus_dir, "nessus", "plugins", "plugin_feed_info.inc")  # Construct full path
    
    lines = [
        f'PLUGIN_SET = "{version}";',
        'PLUGIN_FEED = "ProfessionalFeed (Direct)";',
        'PLUGIN_FEED_TRANSPORT = "Tenable Network Security Lightning";'
    ]
    
    with open(file_path, 'w') as file:
        file.write('\n'.join(lines))
    
def main():
    version = run_cmd("curl -s -k  https://plugins.nessus.org/v2/plugins.php")
    activation_code = generate_nessus_pro()

    if not is_admin():
        run_as_admin()
        return  # Exit the current process

    nessus_dir = r"C:\ProgramData\Tenable\Nessus"
    plugin_dir = os.path.join(nessus_dir, "nessus", "plugins")
    plugin_info_file = os.path.join(nessus_dir, "nessus", "plugin_feed_info.inc")

    commands = [
        'net stop "Tenable Nessus"',
        f'attrib -s -r -h "{plugin_dir}\\*.*"',  # Remove attributes from plugin files
        f'attrib -s -r -h "{plugin_info_file}"',
        f'nessuscli fetch --register "{activation_code}"'
    ]

    for cmd in commands:
        run_cmd(cmd)

    write_plugin_info(version)

    commands = [
        f'move /Y "{plugin_dir}\\plugin_feed_info.inc" "{nessus_dir}\\nessus"',
        f'attrib +s +r +h "{plugin_dir}\\*"',  # Restore attributes
        f'attrib +s +r +h "{plugin_info_file}"',
        'net start "Tenable Nessus"'
    ]

    for cmd in commands:
        run_cmd(cmd)

if __name__ == '__main__':
    main()
