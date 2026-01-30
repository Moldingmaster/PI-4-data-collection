#!/bin/bash
# install.sh - PRODUCTION READY FOR 15 PIS
# Main installer for Pi 4 HMI Logger with NO-DISCONNECT sync

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INSTALL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root (use sudo)"
fi

log "=========================================="
log "Pi 4 HMI Logger - NO-DISCONNECT SYNC"
log "=========================================="

apt update && apt upgrade -y

apt install -y cifs-utils samba-client rsync dosfstools inotify-tools

mkdir -p /etc/hmi_logger /mnt/{usb_share,smb_share,usb_readonly,usb_temp} /var/log/hmi_log_sync
chmod 755 /mnt/{usb_share,smb_share,usb_readonly,usb_temp} /var/log/hmi_log_sync

log "Installing scripts..."
cp "$SCRIPT_DIR/scripts/setup_usb_gadget.sh" /usr/local/bin/
cp "$SCRIPT_DIR/scripts/sync_logs.sh" /usr/local/bin/sync_logs_no_disconnect.sh
cp "$SCRIPT_DIR/scripts/watch_usb_files.sh" /usr/local/bin/watch_usb_no_disconnect.sh
cp "$SCRIPT_DIR/scripts/auto_config.sh" /usr/local/bin/

chmod +x /usr/local/bin/{setup_usb_gadget.sh,sync_logs_no_disconnect.sh,watch_usb_no_disconnect.sh,auto_config.sh}

cp "$SCRIPT_DIR/config/config.template" /etc/hmi_logger/
cp "$SCRIPT_DIR/systemd/hmi-auto-config.service" /etc/systemd/system/
cp "$SCRIPT_DIR/systemd/hmi-realtime-sync.service" /etc/systemd/system/

log "Setting up USB gadget (1GB)..."
export USB_SIZE_MB=1024
/usr/local/bin/setup_usb_gadget.sh

systemctl daemon-reload
systemctl enable hmi-auto-config.service usb-gadget.service hmi-realtime-sync.service

HOSTNAME=$(hostname)
if [[ $HOSTNAME =~ ^press[0-9]+pi$ ]]; then
    /usr/local/bin/auto_config.sh
    touch /etc/hmi_logger/.configured
fi

cat > /etc/logrotate.d/hmi-log-sync << 'EOF'
/var/log/hmi_log_sync/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
}
EOF

log "=========================================="
log "Installation complete!"
log "1GB USB | Real-time sync | No disconnect"
log "=========================================="
