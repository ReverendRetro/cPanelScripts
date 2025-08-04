#!/bin/bash

#
# usrinfo - A script to get cPanel user and domain information.
#
# This script retrieves various details about a cPanel user, including
# their primary domain, IP address, disk space usage, and PHP configuration.
# It can accept either a cPanel username or a domain name as an argument.
#

# --- Configuration ---
# No special configuration is needed, but ensure you are running this on a
# cPanel server with the necessary permissions to use the uapi and whmapi1.

# --- Functions ---

# Function to display a formatted error message and exit.
# Arguments:
#   $1: The error message to display.
function error_exit {
    echo "Error: $1" >&2
    exit 1
}

# Function to display usage information.
function show_usage {
    echo "Usage: usrinfo <cpanel_username|domain_name>"
    exit 1
}

# --- Main Script Logic ---

# Check if an argument was provided.
if [ -z "$1" ]; then
    show_usage
fi

# The input can be a domain or a username.
INPUT="$1"

# --- Determine if input is a domain or username ---

# We'll first assume the input is a username and check if it's valid.
# If not, we'll treat it as a domain and try to find the user.
cpanel_user=""
main_domain=""

# Check if the input corresponds to a valid cPanel user.
if id -u "$INPUT" >/dev/null 2>&1; then
    # It's a valid system user, assume it's the cPanel username.
    cpanel_user="$INPUT"
    # Get the main domain for this user using the UAPI.
    main_domain_info=$(uapi --user="$cpanel_user" Domains get_main_domain)
    main_domain=$(echo "$main_domain_info" | grep 'main_domain:' | awk '{print $2}')
else
    # Input is not a valid system user, so treat it as a domain.
    # Find the user that owns this domain.
    cpanel_user=$(whmapi1 domain_info domain="$INPUT" | grep 'user:' | awk '{print $2}')
    if [ -z "$cpanel_user" ]; then
        error_exit "Could not find a cPanel user for the domain '$INPUT'."
    fi
    main_domain="$INPUT"
fi

# If we still don't have a user or domain, something went wrong.
if [ -z "$cpanel_user" ] || [ -z "$main_domain" ]; then
    error_exit "Could not resolve user or domain for '$INPUT'."
fi


# --- Gather Information ---

# Get the 'A' record from the local cPanel DNS zone. This shows what is configured on the server.
local_a_record_info=$(whmapi1 getzonerecord domain="$main_domain" name="$main_domain." type=A)
local_a_record=$(echo "$local_a_record_info" | grep 'address:' | awk '{print $2}' | head -n 1) # Use head to get only the first record if multiple exist
if [ -z "$local_a_record" ]; then
    local_a_record="Not Found in local zone"
fi

# Get the public 'A' record for the domain using a public resolver (Google's DNS).
# This shows what the rest of the world sees.
public_a_record=$(dig +short A "$main_domain" @8.8.8.8)
if [ -z "$public_a_record" ]; then
    public_a_record="Not Found in public DNS"
fi


# Get disk quota information using cPanel UAPI.
quota_info=$(uapi --user="$cpanel_user" Quota get_quota_info)

# Parse disk space used.
disk_used_raw=$(echo "$quota_info" | grep 'megabytes_used:' | awk '{print $2}')
if [ -n "$disk_used_raw" ]; then
    # Convert MB to a more readable format (GB)
    disk_used=$(awk "BEGIN {printf \"%.2fGB\", $disk_used_raw / 1024}")
else
    disk_used="N/A"
fi

# Parse disk space allocated.
disk_limit_raw=$(echo "$quota_info" | grep 'megabytes_limit:' | awk '{print $2}')
if [ "$disk_limit_raw" == "unlimited" ]; then
    disk_allocated="Unlimited"
elif [ -n "$disk_limit_raw" ]; then
    # Convert MB to a more readable format (GB)
    disk_allocated=$(awk "BEGIN {printf \"%.2fGB\", $disk_limit_raw / 1024}")
else
    disk_allocated="N/A"
fi


# Get the PHP version for the main domain.
php_version_info=$(uapi --user="$cpanel_user" LangPHP get_vhost_versions)
php_version=$(echo "$php_version_info" | grep -A 1 "vhost: $main_domain" | grep 'version:' | awk '{print $2}')
if [ -z "$php_version" ]; then
    php_version="System Default"
fi


# Determine the PHP error log location.
# This often depends on the PHP-FPM setting and can be tricky to get programmatically
# for every setup. This is a common location pattern.
php_log_location="/home/$cpanel_user/logs/${main_domain}.php.error.log"
if [ ! -f "$php_log_location" ]; then
    # A more generic potential location if the above doesn't exist
    php_log_location="/home/$cpanel_user/public_html/error_log"
    if [ ! -f "$php_log_location" ]; then
       php_log_location="Not found at common locations."
    fi
fi


# --- Display Information ---

echo "cPanel User: $cpanel_user"
echo "cPanel Domain: $main_domain"
echo "Local A Record (in cPanel Zone): $local_a_record"
echo "Public A Record (from Google DNS): $public_a_record"
echo "Disk space used: $disk_used"
echo "Disk space allocated: $disk_allocated"
echo "PHP Version: $php_version"
echo "PHP Log Location: $php_log_location"

exit 0
