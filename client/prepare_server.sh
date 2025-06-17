#!/bin/bash

echo "check if example.com is replaced correctly"

# Detect the operating system
OS_NAME="$(uname -s)"

if [ "$OS_NAME" != "Darwin" ]; then
  echo "This script must be run on macOS. Detected OS: $OS_NAME"
  exit 1
fi

echo "Running on macOS. Continuing..."

# Prompt user for the domain name and email to use
read -p "Enter the email for letsencrypt hosting Navidrome: " new_email
read -p "Enter the Navidrome domain (no https://, e.g. example.com): " new_domain

# Patterns to replace (escaped for grep/sed)
email_pattern='hello@example\.com'
domain_pattern='example\.com'

# Directories to process
TARGET_DIRS=( "../client" "../server" )

# 1) Find text files containing either pattern, replace both in one go, and drop .bak files
find "${TARGET_DIRS[@]}" -type f -exec grep -IlE "${email_pattern}|${domain_pattern}" {} \; |
while IFS= read -r file; do
  sed -i.bak \
    -e "s|${email_pattern}|${new_email}|g" \
    -e "s|${domain_pattern}|${new_domain}|g" \
    "$file"
  rm -f "${file}.bak"
done

# 2) As a safety catch, also do a fixed-string search for the email literal and replace
find "${TARGET_DIRS[@]}" -type f -exec grep -IlF 'hello@example.com' {} \; |
while IFS= read -r file; do
  sed -i.bak "s|hello@example\.com|${new_email}|g" "$file"
  rm -f "${file}.bak"
done

echo "Replacement complete across ${TARGET_DIRS[*]}."

echo "Next Steps:"
echo "1. generate-ssl-certificates.sh"
echo "2. package-server.sh"
echo "3. deploy-server.sh"

