#!/bin/bash
# auto_config.sh
# Automatically configure the HMI logger based on hostname
#
# Expected hostname format: press<NUMBER>pi (e.g., press4pi, press12pi)
# This allows deploying identical SD card images that self-configure on first boot

set -euo pipefail

CONFIG_DIR="/etc/hmi_logger"
CONFIG_FILE="$CONFIG_DIR/config"
TEMPLATE_FILE="$CONFIG_DIR/config.template"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# Get current hostname
HOSTNAME=$(hostname)
log "Current hostname: $HOSTNAME"

# Extract press number from hostname (format: press<N>pi or press<N>-pi)
if [[ $HOSTNAME =~ ^press([0-9]+)(pi|-pi)?$ ]]; then
    PRESS_NUMBER="${BASH_REMATCH[1]}"
    log "Detected Press Number: $PRESS_NUMBER"
else
    error_exit "Hostname '$HOSTNAME' does not match expected format 'press<NUMBER>pi'"
fi

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Check for template file
if [ ! -f "$TEMPLATE_FILE" ]; then
    log "Creating default template file..."
    cat > "$TEMPLATE_FILE" << 'EOF'
# HMI Logger Configuration Template
# Variables: {{PRESS_NUMBER}}, {{PRESS_NAME}}, {{HOSTNAME}}

# Press identification
PRESS_NUMBER={{PRESS_NUMBER}}
PRESS_NAME="Press_{{PRESS_NUMBER}}"

# SMB Server Configuration
SMB_SERVER=10.69.1.52
SMB_USER=ftp@maverickmolding.com
SMB_PASS=blueisland
SMB_DOMAIN=MAVERICKMOLDING
SMB_SHARE=Press_{{PRESS_NUMBER}}

# Local paths (usually don't need to change)
LOCAL_MOUNT=/mnt/smb_share
USB_IMAGE=/piusb.bin
USB_MOUNT=/mnt/usb_share
EOF
fi

# Generate config from template
log "Generating configuration for Press $PRESS_NUMBER..."

# Read template and substitute variables
sed -e "s/{{PRESS_NUMBER}}/$PRESS_NUMBER/g" \
    -e "s/{{HOSTNAME}}/$HOSTNAME/g" \
    "$TEMPLATE_FILE" > "$CONFIG_FILE"

# Set secure permissions
chmod 600 "$CONFIG_FILE"

log "Configuration generated at $CONFIG_FILE"
log ""
log "=== Configuration Summary ==="
grep -v "^#" "$CONFIG_FILE" | grep -v "^$" | head -10
log "============================="

# Verify SMB connectivity (optional, non-fatal)
source "$CONFIG_FILE"
log ""
log "Testing network connectivity to SMB server..."
if ping -c 1 -W 5 "$SMB_SERVER" > /dev/null 2>&1; then
    log "SMB server $SMB_SERVER is reachable"
else
    log "WARNING: Cannot reach SMB server $SMB_SERVER - check network configuration"
fi

log ""
log "Auto-configuration complete!"
