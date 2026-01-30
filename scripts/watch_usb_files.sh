#!/bin/bash
# watch_usb_no_disconnect.sh
# Monitor the USB image file for changes and trigger sync
# WITHOUT disconnecting from HMI

WATCH_DIR="/mnt/usb_readonly"
USB_IMAGE="/piusb.bin"
SYNC_SCRIPT="/usr/local/bin/sync_logs_no_disconnect.sh"
LOG_FILE="/var/log/hmi_log_sync/realtime_sync.log"
DEBOUNCE_SECONDS=5

mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$WATCH_DIR"

log() {
    echo "$(date -Iseconds) $1" | tee -a "$LOG_FILE"
}

# Mount the USB image read-only for monitoring
log "Mounting USB image read-only for monitoring..."
mount -o ro,loop "$USB_IMAGE" "$WATCH_DIR" || {
    log "ERROR: Failed to mount USB image for monitoring"
    exit 1
}

log "Starting real-time file watcher on $WATCH_DIR (HMI remains connected)"

# Use inotifywait to monitor for file changes
inotifywait -m -r -e modify,close_write,moved_to,create "$WATCH_DIR" --format '%w%f' 2>&1 | while read FILE
do
    # Skip system files
    if [[ "$FILE" =~ "System Volume Information" ]] || \
       [[ "$FILE" =~ "/." ]] || \
       [[ "$FILE" =~ "Thumbs.db" ]]; then
        continue
    fi
    
    log "File change detected: $FILE"
    log "Waiting ${DEBOUNCE_SECONDS}s for HMI to finish writing..."
    sleep $DEBOUNCE_SECONDS
    
    log "Triggering sync (HMI stays connected)..."
    
    # Remount to pick up changes, then sync
    umount "$WATCH_DIR" 2>/dev/null
    mount -o ro,loop "$USB_IMAGE" "$WATCH_DIR"
    
    "$SYNC_SCRIPT" >> "$LOG_FILE" 2>&1 &
    
    log "Sync triggered in background"
done
