#!/bin/bash
# setup_usb_gadget.sh
# Configure Raspberry Pi 4 as USB Mass Storage Device
# Pi 4 uses dwc2 controller on the USB-C port for gadget mode

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USB_IMAGE="/piusb.bin"
USB_SIZE_MB="${USB_SIZE_MB:-2048}"  # Default 2GB, can be overridden
USB_MOUNT="/mnt/usb_share"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    error_exit "This script must be run as root"
fi

log "Setting up Raspberry Pi 4 as USB Mass Storage Device..."

# Step 1: Enable dwc2 overlay in config.txt
CONFIG_FILE="/boot/firmware/config.txt"
# Fallback for older Pi OS versions
[ -f "$CONFIG_FILE" ] || CONFIG_FILE="/boot/config.txt"

log "Configuring $CONFIG_FILE..."

# Add dtoverlay=dwc2 if not present
if ! grep -q "^dtoverlay=dwc2" "$CONFIG_FILE"; then
    echo "dtoverlay=dwc2" >> "$CONFIG_FILE"
    log "Added dtoverlay=dwc2 to $CONFIG_FILE"
else
    log "dtoverlay=dwc2 already configured"
fi

# Step 2: Add dwc2 to /etc/modules
MODULES_FILE="/etc/modules"
if ! grep -q "^dwc2" "$MODULES_FILE"; then
    echo "dwc2" >> "$MODULES_FILE"
    log "Added dwc2 to $MODULES_FILE"
else
    log "dwc2 module already in $MODULES_FILE"
fi

# Step 3: Create the USB disk image if it doesn't exist
if [ ! -f "$USB_IMAGE" ]; then
    log "Creating ${USB_SIZE_MB}MB USB disk image at $USB_IMAGE..."
    dd if=/dev/zero of="$USB_IMAGE" bs=1M count="$USB_SIZE_MB" status=progress

    log "Formatting USB image as FAT32..."
    mkfs.vfat -F 32 -n "HMIDATA" "$USB_IMAGE"
    log "USB disk image created successfully"
else
    log "USB disk image already exists at $USB_IMAGE"
fi

# Step 4: Create mount point
mkdir -p "$USB_MOUNT"

# Step 5: Add fstab entry for auto-mounting the image
FSTAB_ENTRY="$USB_IMAGE $USB_MOUNT vfat loop,rw,users,umask=000 0 0"
if ! grep -q "$USB_IMAGE" /etc/fstab; then
    echo "$FSTAB_ENTRY" >> /etc/fstab
    log "Added fstab entry for USB image"
else
    log "fstab entry already exists"
fi

# Step 6: Create systemd service to load USB gadget on boot
cat > /etc/systemd/system/usb-gadget.service << 'EOF'
[Unit]
Description=USB Mass Storage Gadget
After=local-fs.target
Requires=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/sleep 5
ExecStart=/usr/local/bin/start_usb_gadget.sh
ExecStop=/sbin/modprobe -r g_mass_storage

[Install]
WantedBy=multi-user.target
EOF

# Step 7: Create the gadget start script
cat > /usr/local/bin/start_usb_gadget.sh << 'EOF'
#!/bin/bash
# Start USB Mass Storage Gadget

USB_IMAGE="/piusb.bin"
USB_MOUNT="/mnt/usb_share"

# Ensure image is unmounted from Pi before presenting to USB host
umount "$USB_MOUNT" 2>/dev/null || true

# Load the g_mass_storage module
modprobe g_mass_storage file="$USB_IMAGE" stall=0 removable=1 ro=0

echo "USB Mass Storage gadget started"
EOF
chmod +x /usr/local/bin/start_usb_gadget.sh

# Step 8: Create script to temporarily access USB data from Pi
cat > /usr/local/bin/usb_gadget_mount.sh << 'EOF'
#!/bin/bash
# Mount USB image locally (disconnects from USB host temporarily)

USB_IMAGE="/piusb.bin"
USB_MOUNT="/mnt/usb_share"

# Remove gadget module to disconnect from host
modprobe -r g_mass_storage 2>/dev/null || true

# Mount locally
mount -o loop "$USB_IMAGE" "$USB_MOUNT"
echo "USB image mounted locally at $USB_MOUNT"
EOF
chmod +x /usr/local/bin/usb_gadget_mount.sh

cat > /usr/local/bin/usb_gadget_unmount.sh << 'EOF'
#!/bin/bash
# Unmount USB image and re-present to USB host

USB_IMAGE="/piusb.bin"
USB_MOUNT="/mnt/usb_share"

# Sync and unmount
sync
umount "$USB_MOUNT" 2>/dev/null || true

# Re-enable USB gadget
modprobe g_mass_storage file="$USB_IMAGE" stall=0 removable=1 ro=0
echo "USB gadget re-enabled"
EOF
chmod +x /usr/local/bin/usb_gadget_unmount.sh

# Enable the service
systemctl daemon-reload
systemctl enable usb-gadget.service

log "USB Gadget setup complete!"
log ""
log "IMPORTANT: The Pi 4's USB-C port will act as the USB drive."
log "Connect the USB-C port to your HMI."
log "The USB-A ports remain available for keyboard/mouse/other devices."
log ""
log "A reboot is required for changes to take effect."
