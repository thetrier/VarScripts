#!/bin/bash
## th3tr1er
# Version: 1.0
# Linux Forensics Information Gathering Script
# 04.03.2026
# Added:
## progress bar
## modified iterations
## added functions to avoid countless "echo" output iterrations
## added checks if certain commands exist before running them
## extracting OS Version and Distribution
## copying .timer files to check for persistence
## would be a good idea to copyservices files as well (just in case)

# Check if running as root
main() {
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run with privileges. Please use sudo -E $0 or su"
    return 1
fi

echo "Running with elevated privileges, continuing ..."
# Define results folder and file
FOLDER="$(hostname)"
mkdir -p "$FOLDER"
chmod 755 "$FOLDER"
RESULTS_FILE="$PWD/$FOLDER/$(hostname)_results"

### Script Progress

# ===== Section Counter Setup =====
TOTAL_SECTIONS=15   #number of sections
CURRENT_SECTION=0

progress_bar() {
    CURRENT_SECTION=$((CURRENT_SECTION + 1))
    PERCENT=$(( CURRENT_SECTION * 100 / TOTAL_SECTIONS ))
    BAR=$(printf "%-${TOTAL_SECTIONS}s" "#" | sed "s/ /#/g")
    echo -ne "Progress: [${BAR:0:CURRENT_SECTION}${BAR:CURRENT_SECTION}] $PERCENT% \r"
}

# Clear results file if it exists
if [[ -f "$RESULTS_FILE" ]]; then
    > "$RESULTS_FILE"
else
    touch "$RESULTS_FILE"
fi

# Function for section headers
section() {
    echo "==================== $1 ====================" >> "$RESULTS_FILE"
}

# Function to run commands safely
run_cmd() {
    CMD_NAME=$1
    shift
    if command -v "$CMD_NAME" >/dev/null 2>&1; then
        "$@" >> "$RESULTS_FILE" 2>&1
    else
        echo "command $CMD_NAME can not be executed; binary not found" >> "$RESULTS_FILE"
    fi
}

echo "Gathering Operating System Information... Please wait...."

# ===== Linux System Information =====
{
    section "Linux System Information"
    echo "$FOLDER"
    echo

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "Source: /etc/os-release"
        echo "Distribution: ${NAME:-Unknown}"
        echo "Version: ${VERSION:-Unknown}"
        echo "Version ID: ${VERSION_ID:-Unknown}"
        echo "Codename: ${VERSION_CODENAME:-Unknown}"
    elif command -v hostnamectl >/dev/null 2>&1; then
        echo "Source: hostnamectl"
        hostnamectl | grep "Operating System"
    elif command -v lsb_release >/dev/null 2>&1; then
        echo "Source: lsb_release"
        lsb_release -a
    elif [ -f /etc/redhat-release ]; then
        echo "Source: /etc/redhat-release"
        cat /etc/redhat-release
    elif [ -f /etc/centos-release ]; then
        echo "Source: /etc/centos-release"
        cat /etc/centos-release
    elif [ -f /etc/debian_version ]; then
        echo "Source: /etc/debian_version"
        cat /etc/debian_version
    elif [ -f /etc/issue ]; then
        echo "Source: /etc/issue"
        cat /etc/issue
    else
        echo "OS distribution information could not be determined."
    fi

    echo
    echo "Kernel Version: $(uname -r)"
    echo "Full Kernel Info: $(uname -a)"
    echo "Architecture: $(uname -m)"
} >> "$RESULTS_FILE" 2>&1
progress_bar
# ===== Processes Running =====
section "Processes Running"
run_cmd ps ps auxweft
progress_bar
# ===== Network Connections =====
section "Network Connections"
if command -v netstat >/dev/null 2>&1; then
    netstat -laptuen >> "$RESULTS_FILE" 2>&1
elif command -v ss >/dev/null 2>&1; then
    ss -laptuen >> "$RESULTS_FILE" 2>&1
else
    echo "command netstat/ss cannot be executed; binary not found" >> "$RESULTS_FILE"
fi
progress_bar
# ===== Processes with Connections =====
section "Processes Running With Connections"
if command -v lsof >/dev/null 2>&1; then
    run_cmd lsof lsof -i
fi
progress_bar
# ===== Services Running - Unit Files =====
section "Services Running - Unit Files"
if command -v systemctl >/dev/null 2>&1; then
    run_cmd systemctl systemctl list-unit-files
    echo "" >> "$RESULTS_FILE"
    echo "----- Unit File Creation Details -----" >> "$RESULTS_FILE"
    systemctl list-unit-files --type=service --no-legend | awk '{print $1}' | while read unit; do
        FILE_PATH=$(systemctl show -p FragmentPath "$unit" 2>/dev/null | cut -d= -f2)
        if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
            echo "Unit: $unit" >> "$RESULTS_FILE"
            if command -v stat >/dev/null 2>&1; then
                stat "$FILE_PATH" >> "$RESULTS_FILE" 2>&1
            else
                echo "command stat cannot be executed; binary not found" >> "$RESULTS_FILE"
            fi
            echo "" >> "$RESULTS_FILE"
        else
            echo "Unit: $unit - file path not found or inaccessible" >> "$RESULTS_FILE"
        fi
    done
else
    echo "command systemctl cannot be executed; binary not found" >> "$RESULTS_FILE"
fi
progress_bar
# ===== Services Running - Active =====
section "Services Running - Active"
systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print $1}' | while read svc; do
    if systemctl is-enabled "$svc" >/dev/null 2>&1; then
        echo "$svc" >> "$RESULTS_FILE"
    fi
done
progress_bar
# ===== Services Timer Files =====
section "Services Timer Files"
systemctl list-unit-files --type=timer --no-legend | awk '$2=="enabled" || $2=="static" {print $1}' | while read timer; do
    FILE=$(systemctl show -p FragmentPath "$timer" | cut -d= -f2)
    if [ -n "$FILE" ] && [ -f "$FILE" ]; then
        cp --parents "$FILE" "$PWD/$FOLDER/"
    fi
done
progress_bar
# ===== Users =====
section "Users"
if command -v cat >/dev/null 2>&1; then
    run_cmd cat cat /etc/passwd
else
    echo "command cat cannot be executed; binary not found" >> "$RESULTS_FILE"
fi
progress_bar
# ===== Files with X bit set last 30 days =====
section "Files with X bit set last 30 days"
if command -v find >/dev/null 2>&1; then
    run_cmd find find / -type f -perm -111 -mtime -30 -exec ls -1alh {} \; 2>/dev/null
else
    echo "command find cannot be executed; binary not found" >> "$RESULTS_FILE"
fi
progress_bar
# ===== Logins =====
section "Logins"
if command -v last >/dev/null 2>&1; then
    run_cmd last last -a 2>/dev/null
else
    echo "command last cannot be executed; binary not found" >> "$RESULTS_FILE"
fi
progress_bar
# ===== Failed Logins =====
section "Failed Logins"
if command -v lastb >/dev/null 2>&1; then
    run_cmd last lastb -a 2>/dev/null
else
    echo "command lastb cannot be executed; binary not found" >> "$RESULTS_FILE"
fi
progress_bar
# ===== Cron Jobs All Users =====
section "Cron Jobs All Users"
if command -v crontab >/dev/null 2>&1; then
    for user in $(cut -f1 -d: /etc/passwd); do
        echo "$user" >> "$RESULTS_FILE"
        crontab -u "$user" -l >> "$RESULTS_FILE" 2>&1
    done
else
    echo "command crontab cannot be executed; binary not found" >> "$RESULTS_FILE"
fi
progress_bar
# ===== Commands Executed =====
section "Commands Executed"
# Loop through all home directories
for home_dir in /home/*; do
    user=$(basename "$home_dir")
    HIST_FILE="$home_dir/.bash_history"

    if [ -f "$HIST_FILE" ]; then
        echo "===== Commands executed by user: $user =====" >> "$RESULTS_FILE"
        cat "$HIST_FILE" >> "$RESULTS_FILE" 2>&1
        echo "============================================" >> "$RESULTS_FILE"
        echo "" >> "$RESULTS_FILE"
    else
        # Optionally note that the user has no history yet
        echo "===== No bash history found for user: $user =====" >> "$RESULTS_FILE"
        echo "============================================" >> "$RESULTS_FILE"
        echo "" >> "$RESULTS_FILE"
    fi
done
# Include root user
ROOT_HIST="/root/.bash_history"
if [ -f "$ROOT_HIST" ]; then
    echo "===== Commands executed by user: root =====" >> "$RESULTS_FILE"
    cat "$ROOT_HIST" >> "$RESULTS_FILE" 2>&1
    echo "============================================" >> "$RESULTS_FILE"
    echo "" >> "$RESULTS_FILE"
fi
progress_bar
# ===== Commands Executed by ROOT =====
if [ -d /root ]; then
    cat /root/.*sh_history >> "$RESULTS_FILE" 2>&1
fi
progress_bar
# ===== Collection Metadata =====
section "Collection Metadata"
echo "All results extracted by $(whoami) with previous user $SUDO_USER on:" >> "$RESULTS_FILE"
date '+%Y-%m-%d %H:%M:%S' >> "$RESULTS_FILE"

echo "All done. File name and location: $RESULTS_FILE"

exit 0
}
main "$@"