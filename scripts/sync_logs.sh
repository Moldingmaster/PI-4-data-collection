#!/bin/bash
# sync_logs.sh
# Sync HMI log files from USB gadget image to SMB share
# This script temporarily disconnects the USB drive from the HMI to sync data

set -euo pipefail

# Configuration
CONFIG_FILE="/etc/hmi_logger/config"
USB_IMAGE="/piusb.bin"
USB_MOUNT="/mnt/usb_share"
SMB_MOUNT="/mnt/smb_share"
LOG_DIR="/var/log/hmi_log_sync"
LOCK_FILE="/var/run/hmi_sync.lock"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Configuration file $CONFIG_FILE not found"
    exit 1
fi

# Setup logging
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="$LOG_DIR/sync_$TIMESTAMP.log"
mkdir -p "$LOG_DIR"

log() {
    echo "$(date -Iseconds) $1" | tee -a "$LOG_FILE"
}

cleanup() {
    log "Cleaning up..."
    # Unmount SMB if mounted
    umount "$SMB_MOUNT" 2>/dev/null || true
    # Re-enable USB gadget
    /usr/local/bin/usb_gadget_unmount.sh >> "$LOG_FILE" 2>&1 || true
    # Remove lock file
    rm -f "$LOCK_FILE"
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
    log "Another sync is already running (lock file exists). Exiting."
    exit 0
fi
touch "$LOCK_FILE"

log "=========================================="
log "Starting HMI log synchronization"
log "Press: ${PRESS_NAME:-unknown}"
log "=========================================="

# Step 1: Disconnect USB gadget and mount locally
log "Disconnecting USB from HMI and mounting locally..."
/usr/local/bin/usb_gadget_mount.sh >> "$LOG_FILE" 2>&1 || {
    log "ERROR: Failed to mount USB image locally"
    exit 1
}

# Wait for mount to settle
sleep 2

# Verify USB mount
if ! mountpoint -q "$USB_MOUNT"; then
    log "ERROR: USB share not mounted at $USB_MOUNT"
    exit 1
fi

# Check if there are any files to sync
FILE_COUNT=$(find "$USB_MOUNT" -type f ! -name ".*" 2>/dev/null | wc -l)
log "Found $FILE_COUNT files to sync"

if [ "$FILE_COUNT" -eq 0 ]; then
    log "No files to sync, re-enabling USB gadget"
    exit 0
fi

# Step 2: Mount SMB share
log "Mounting SMB share: //${SMB_SERVER}/${SMB_SHARE}"
mkdir -p "$SMB_MOUNT"

mount -t cifs "//${SMB_SERVER}/${SMB_SHARE}" "$SMB_MOUNT" \
    -o username="${SMB_USER}",password="${SMB_PASS}",domain="${SMB_DOMAIN:-WORKGROUP}",vers=3.0,file_mode=0777,dir_mode=0777 \
    >> "$LOG_FILE" 2>&1 || {
    log "ERROR: Failed to mount SMB share"
    exit 1
}

log "SMB share mounted successfully"

# Step 3: Sync files
log "Starting file synchronization..."

# Create date-based subfolder on SMB share
SYNC_DATE=$(date '+%Y-%m-%d')
DEST_DIR="$SMB_MOUNT/$SYNC_DATE"
mkdir -p "$DEST_DIR"

rsync -av --remove-source-files \
    --exclude='System Volume Information' \
    --exclude='.Spotlight-*' \
    --exclude='.fseventsd' \
    --exclude='.DS_Store' \
    --exclude='Thumbs.db' \
    --exclude='._*' \
    --log-file="$LOG_FILE" \
    "$USB_MOUNT/" "$DEST_DIR/" 2>&1 || {
    log "WARNING: rsync encountered errors, some files may not have synced"
}

# Clean up empty directories on USB
find "$USB_MOUNT" -mindepth 1 -type d -empty -delete 2>/dev/null || true

# Step 4: Unmount SMB
log "Unmounting SMB share..."
sync
umount "$SMB_MOUNT" >> "$LOG_FILE" 2>&1 || log "WARNING: Failed to cleanly unmount SMB"

log "=========================================="
log "Synchronization completed"
log "=========================================="

# Cleanup will re-enable USB gadget via trap
exit 0
