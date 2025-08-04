#!/bin/bash
#
# cPanel Health Check Script
#
# This script provides a quick overview of a cPanel server's health,
# checking system resources, logs, email queue, and web server activity.
#

# --- Color Codes for Output ---
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Helper Function for Headers ---
print_header() {
    echo -e "\n${BLUE}=====================================================${NC}"
    echo -e "${BLUE}== ${YELLOW}Health check start.${NC}"
    echo -e "${BLUE}=====================================================${NC}"
}

# --- Basic System Information ---
show_system_info() {
    print_header "BASIC SYSTEM INFO"
    echo -e "${YELLOW}Load & Uptime:${NC}"
    uptime
    echo
    echo -e "${YELLOW}Disk Usage:${NC}"
    df -h
    echo
    echo -e "${YELLOW}Memory Usage:${NC}"
    free -mh
    echo
    echo -e "${YELLOW}CPU Core Count:${NC}"
    nproc
}

# --- Check System Logs for Critical Events ---
check_system_logs() {
    print_header "SYSTEM LOGS"
    echo -e "${YELLOW}Recent OOM (Out Of Memory) Events:${NC}"
    if grep -qia 'oom-killer' /var/log/messages; then
        grep -ia 'oom-killer\|killed' /var/log/messages | tail -10
    else
        echo "No OOM events found in /var/log/messages."
    fi
}

# --- Check Email Server (Exim) Status ---
check_exim_status() {
    print_header "EMAIL (EXIM) STATUS"
    echo -e "${YELLOW}Outgoing Emails in Queue:${NC}"
    exim -bpc
    echo
    echo -e "${YELLOW}Top IPs Triggering Connection Rate Limiting:${NC}"
    if grep -q "connection count" /var/log/exim_mainlog; then
        grep "connection count" /var/log/exim_mainlog | awk '{print $7}' | cut -d'[' -f2 | cut -d']' -f1 | sort | uniq -c | sort -rn | head
    else
        echo "No recent connection rate-limiting events found."
    fi
}

# --- Analyze Apache Web Server Logs ---
check_apache() {
    print_header "APACHE WEB SERVER ANALYSIS"

    # Determine correct log paths for EA3 vs EA4
    if [ -f /etc/cpanel/ea4/is_ea4 ]; then
        APACHE_DOMLOGS="/var/log/apache2/domlogs"
        APACHE_ERROR_LOG="/var/log/apache2/error_log"
    else
        APACHE_DOMLOGS="/usr/local/apache/domlogs"
        APACHE_ERROR_LOG="/usr/local/apache/logs/error_log"
    fi

    # Check if domlogs directory exists
    if [ ! -d "$APACHE_DOMLOGS" ]; then
        echo -e "${RED}Apache domlogs directory not found at ${APACHE_DOMLOGS}${NC}"
        return
    fi
    
    # Grab today's logs once to avoid repeated file access
    TODAYS_LOGS=$(grep -sh "$(date +%d/%b/%Y):" "${APACHE_DOMLOGS}"/*/* 2>/dev/null)

    if [ -z "$TODAYS_LOGS" ]; then
        echo "No Apache traffic recorded yet for today."
        return
    fi

    echo -e "${YELLOW}Top 15 IPs Hitting Server Today:${NC}"
    echo "$TODAYS_LOGS" | awk '{print $1}' | cut -d: -f2 | sort | uniq -c | sort -rn | head -15

    echo
    echo -e "${YELLOW}Top 10 Domains by POST Requests Today:${NC}"
    echo "$TODAYS_LOGS" | grep 'POST' | awk '{print $1}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10
    
    echo
    echo -e "${YELLOW}Top 10 Domains by GET Requests Today:${NC}"
    echo "$TODAYS_LOGS" | grep 'GET' | awk '{print $1}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10
    
    echo
    echo -e "${YELLOW}Top 10 URIs Receiving POST Requests:${NC}"
    echo "$TODAYS_LOGS" | grep 'POST' | awk '{print $7}' | sort | uniq -c | sort -rn | head -10
    
    echo
    echo -e "${YELLOW}Top 10 Suspected Bot Hits by Domain:${NC}"
    echo "$TODAYS_LOGS" | egrep -i 'crawl|bot|spider|yahoo|bing|google' | awk '{print $1}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10

    echo
    echo -e "${YELLOW}Recent Apache Server Limit Errors:${NC}"
    if [ -f "$APACHE_ERROR_LOG" ]; then
        grep -ia 'server reached\|scoreboard' "$APACHE_ERROR_LOG" | tail -5
    else
        echo "Apache error log not found at ${APACHE_ERROR_LOG}"
    fi
}

# --- Check PHP-FPM Logs for Errors ---
check_php_fpm() {
    print_header "PHP-FPM STATUS"
    
    # Loop through all installed EasyApache PHP versions
    for php_dir in /opt/cpanel/ea-php*/; do
        if [ -d "$php_dir" ]; then
            php_version=$(basename "$php_dir")
            log_file="${php_dir}root/usr/var/log/php-fpm/error.log"
            
            echo -e "${YELLOW}Checking ${php_version}...${NC}"

            if [ -f "$log_file" ]; then
                # Search for max_children errors and count them
                errors=$(grep 'reached max_children setting' "$log_file" 2>/dev/null)
                if [ -n "$errors" ]; then
                    echo "$errors" | awk -F': ' '{print $3}' | sort | uniq -c | sort -rn | head
                else
                    echo "No 'max_children' errors found."
                fi
            else
                echo "Log file not found for this version."
            fi
            echo
        fi
    done
}


# --- Main Execution ---
main() {
    show_system_info
    check_system_logs
    check_exim_status
    check_apache
    check_php_fpm
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}== ${YELLOW}Health check complete.${NC}"
    echo -e "${BLUE}=====================================================${NC}"
}

# Run the script
main
