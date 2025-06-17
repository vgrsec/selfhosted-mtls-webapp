#!/usr/bin/env bash
set -euo pipefail

# package_server.sh
# -----------------
# Packages the 'server' directory into a tar.gz,
# excluding macOS metadata and extended attributes.
# Should be run from client/ or anywhere.
# Usage: ./package_server.sh [OUTPUT_FILENAME]

# Determine script directory and base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source and output
SOURCE_DIR="$BASE_DIR/server"
OUTPUT_FILE="${1:-$BASE_DIR/selfhosted-mtls-webapp.tar.gz}"

# Exclude patterns for macOS metadata
EXCLUDES=(
  --exclude="*.DS_Store"
  --exclude="*/.DS_Store"
  --exclude="__MACOSX"
  --exclude="*/__MACOSX"
  --exclude="._*"
)

echo "Deleting '$OUTPUT_FILE' if it exists"
if [[ -f "$OUTPUT_FILE" ]]; then
  echo "[+] Removing existing archive: $OUTPUT_FILE"
  rm "$OUTPUT_FILE"
fi

echo "Packaging '$SOURCE_DIR' into '$OUTPUT_FILE'..."

# Disable macOS extended attributes
export COPYFILE_DISABLE=1

# Create tarball without xattrs
tar --no-xattrs -czf "$OUTPUT_FILE" \
    "${EXCLUDES[@]}" \
    -C "$BASE_DIR" \
    "server"

echo "Done. Created $OUTPUT_FILE"
echo "To unzip into ~/selfhosted-mtls-webapp, run:"
echo "  mkdir -p ~/selfhosted-mtls-webapp && tar --strip-components=1 -xzf $(basename "$OUTPUT_FILE") -C ~/selfhosted-mtls-webapp"