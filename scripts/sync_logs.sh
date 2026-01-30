#!/bin/bash
# sync_logs_no_disconnect.sh
# Sync HMI log files WITHOUT disconnecting from HMI
# Read directly from the USB image file while gadget is active

set -euo pipefail

CONFIG_FILE="/etc/hmi_logger/config"
USB_IMAGE="/piusb.bin"
TEMP_MOUNT="/mnt/usb_temp"
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
    umount "$TEMP_MOUNT" 2>/dev/null || true
    umount "$SMB_MOUNT" 2>/dev/null || true
    rm -f "$LOCK_FILE"
}

trap cleanup EXIT

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
    log "Another sync is already running. Exiting."
    exit 0
fi
touch "$LOCK_FILE"

log "=========================================="
log "Starting HMI log synchronization (NO DISCONNECT)"
log "Press: ${PRESS_NAME:-unknown}"
log "=========================================="

# Mount the USB image READ-ONLY in a temporary location
# This works even while the gadget is active!
log "Mounting USB image read-only at $TEMP_MOUNT..."
mkdir -p "$TEMP_MOUNT"

mount -o ro,loop "$USB_IMAGE" "$TEMP_MOUNT" >> "$LOG_FILE" 2>&1 || {
    log "ERROR: Failed to mount USB image"
    exit 1
}

sleep 1

# Check if there are any files to sync
FILE_COUNT=$(find "$TEMP_MOUNT" -type f ! -name ".*" ! -path "*/System Volume Information/*" 2>/dev/null | wc -l)
log "Found $FILE_COUNT files to sync"

if [ "$FILE_COUNT" -eq 0 ]; then
    log "No files to sync"
    exit 0
fi

# Mount SMB share
log "Mounting SMB share: //${SMB_SERVER}/${SMB_SHARE}"
mkdir -p "$SMB_MOUNT"

mount -t cifs "//${SMB_SERVER}/${SMB_SHARE}" "$SMB_MOUNT" \
    -o username="${SMB_USER}",password="${SMB_PASS}",vers=3.0,file_mode=0777,dir_mode=0777 \
    >> "$LOG_FILE" 2>&1 || {
    log "ERROR: Failed to mount SMB share"
    exit 1
}

log "SMB share mounted successfully"

# Sync directly to Press_7 folder (no date subfolders)
DEST_DIR="$SMB_MOUNT/${PRESS_NAME}"
mkdir -p "$DEST_DIR"

# Sync files (copy, don't remove from source since it's read-only)
log "Starting file synchronization..."
rsync -av \
    --exclude='System Volume Information' \
    --exclude='.Spotlight-*' \
    --exclude='.fseventsd' \
    --exclude='.DS_Store' \
    --exclude='Thumbs.db' \
    --exclude='._*' \
    --log-file="$LOG_FILE" \
    "$TEMP_MOUNT/" "$DEST_DIR/" 2>&1 || {
    log "WARNING: rsync encountered errors"
}

# Create a marker file to track what's been synced
SYNC_MARKER="$SMB_MOUNT/${PRESS_NAME}/.last_sync"
echo "$TIMESTAMP" > "$SYNC_MARKER"

log "Unmounting temporary mount and SMB share..."
sync
umount "$TEMP_MOUNT" >> "$LOG_FILE" 2>&1 || log "WARNING: Failed to unmount temp"
umount "$SMB_MOUNT" >> "$LOG_FILE" 2>&1 || log "WARNING: Failed to unmount SMB"

log "=========================================="
log "Synchronization completed"
log "Files remain on USB drive for HMI access"
log "=========================================="

exit 0
