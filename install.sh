#!/bin/bash
# install.sh
# Main installer for Pi 4 HMI Logger
# Run this script on a fresh Raspberry Pi 4 with Raspberry Pi OS Lite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INSTALL]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root (use sudo)"
fi

# Check if this is a Raspberry Pi 4
if [ -f /proc/device-tree/model ]; then
    MODEL=$(cat /proc/device-tree/model)
    log "Detected: $MODEL"
    if [[ ! "$MODEL" =~ "Raspberry Pi 4" ]]; then
        warn "This script is optimized for Raspberry Pi 4"
        warn "Detected: $MODEL"
        read -p "Continue anyway? [y/N]: " CONTINUE
        [[ ! $CONTINUE =~ ^[Yy]$ ]] && exit 1
    fi
else
    warn "Could not detect Raspberry Pi model"
fi

log "=========================================="
log "Pi 4 HMI Logger Installation"
log "=========================================="

# Step 1: Update system and install dependencies
log "Updating system packages..."
apt update
apt upgrade -y

log "Installing required packages..."
apt install -y \
    cifs-utils \
    samba-client \
    rsync \
    dosfstools \
    inotify-tools

# Step 2: Create directories
log "Creating directories..."
mkdir -p /etc/hmi_logger
mkdir -p /mnt/usb_share
mkdir -p /mnt/smb_share
mkdir -p /var/log/hmi_log_sync

# Set permissions
chmod 755 /mnt/usb_share
chmod 755 /mnt/smb_share
chmod 755 /var/log/hmi_log_sync

# Step 3: Install scripts
log "Installing scripts..."
cp "$SCRIPT_DIR/scripts/setup_usb_gadget.sh" /usr/local/bin/
cp "$SCRIPT_DIR/scripts/sync_logs.sh" /usr/local/bin/
cp "$SCRIPT_DIR/scripts/auto_config.sh" /usr/local/bin/

chmod +x /usr/local/bin/setup_usb_gadget.sh
chmod +x /usr/local/bin/sync_logs.sh
chmod +x /usr/local/bin/auto_config.sh

# Step 4: Install config template
log "Installing configuration template..."
cp "$SCRIPT_DIR/config/config.template" /etc/hmi_logger/

# Step 5: Install systemd services
log "Installing systemd services..."
cp "$SCRIPT_DIR/systemd/hmi-log-sync.service" /etc/systemd/system/
cp "$SCRIPT_DIR/systemd/hmi-log-sync.timer" /etc/systemd/system/
cp "$SCRIPT_DIR/systemd/hmi-auto-config.service" /etc/systemd/system/

# Step 6: Setup USB gadget
log "Setting up USB Mass Storage gadget..."
/usr/local/bin/setup_usb_gadget.sh

# Step 7: Enable services
log "Enabling services..."
systemctl daemon-reload
systemctl enable hmi-auto-config.service
systemctl enable hmi-log-sync.timer

# Step 8: Run auto-config now if hostname is set correctly
HOSTNAME=$(hostname)
if [[ $HOSTNAME =~ ^press[0-9]+pi$ ]]; then
    log "Hostname matches expected pattern, running auto-config..."
    /usr/local/bin/auto_config.sh
    touch /etc/hmi_logger/.configured
else
    warn "Hostname '$HOSTNAME' doesn't match pattern 'press<N>pi'"
    warn "Set hostname before rebooting:"
    warn "  sudo hostnamectl set-hostname press<N>pi"
    warn "  (e.g., sudo hostnamectl set-hostname press4pi)"
fi

# Log rotation setup
log "Setting up log rotation..."
cat > /etc/logrotate.d/hmi-log-sync << 'EOF'
/var/log/hmi_log_sync/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF

log "=========================================="
log "Installation complete!"
log "=========================================="
log ""
log "Next steps:"
log "1. Set the hostname if not already done:"
log "   sudo hostnamectl set-hostname press<N>pi"
log ""
log "2. Reboot the Pi:"
log "   sudo reboot"
log ""
log "3. After reboot, connect the USB-C port to your HMI"
log "   The Pi will appear as a USB drive to the HMI"
log ""
log "4. Check status with:"
log "   systemctl status usb-gadget.service"
log "   systemctl status hmi-log-sync.timer"
log ""
log "5. View sync logs:"
log "   journalctl -u hmi-log-sync.service -f"
log "   ls -la /var/log/hmi_log_sync/"
log ""
