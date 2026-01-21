# Pi 4 HMI Logger

Raspberry Pi 4 based system for collecting HMI (Human Machine Interface) data logs by emulating a USB mass storage device.

## Overview

This system configures a Raspberry Pi 4 to appear as a USB flash drive to an HMI. The HMI writes log files to what it thinks is a USB stick, but the Pi periodically syncs these files to a central SMB server.

## Features

- **USB Mass Storage Emulation**: Pi 4's USB-C port appears as a FAT32 USB drive to HMIs
- **Automatic Sync**: Logs are synced to SMB share every 10 minutes
- **Auto-Configuration**: Pi configures itself based on hostname (e.g., `press4pi` → `Press_4` share)
- **Minimal Downtime**: USB drive is only disconnected briefly during sync
- **Date-Organized Storage**: Files are stored in date-based folders on the SMB share

## Hardware Requirements

- Raspberry Pi 4 (any RAM variant)
- MicroSD card (16GB+ recommended)
- USB-C cable (to connect to HMI)
- Network connectivity (WiFi or Ethernet)

## Important: Pi 4 USB-C Limitation

The Pi 4 can only act as a USB gadget (mass storage device) through its **USB-C power port**. This means:
- You'll need to power the Pi via GPIO pins or a USB-C Y-cable
- The USB-A ports remain available for other peripherals
- The USB-C port connects to the HMI

## Quick Start

### 1. Prepare the SD Card

Flash Raspberry Pi OS Lite (64-bit) to the SD card and enable SSH.

### 2. Set Hostname

Before first boot, or after booting:
```bash
sudo hostnamectl set-hostname press4pi  # Replace 4 with your press number
```

### 3. Transfer and Run Installer

```bash
# From your computer
scp -r pi4-hmi-logger pi@<pi-ip>:~/

# SSH into the Pi
ssh pi@<pi-ip>

# Run installer
cd ~/pi4-hmi-logger
chmod +x install.sh
sudo ./install.sh
```

### 4. Reboot

```bash
sudo reboot
```

### 5. Connect to HMI

Connect the Pi's USB-C port to the HMI's USB port. The HMI should detect a 2GB FAT32 drive.

## Configuration

### Auto-Configuration

The system automatically configures itself based on hostname:

| Hostname | Press Number | SMB Share |
|----------|--------------|-----------|
| press1pi | 1 | Press_1 |
| press4pi | 4 | Press_4 |
| press12pi | 12 | Press_12 |

### Manual Configuration

Edit `/etc/hmi_logger/config`:
```bash
PRESS_NUMBER=4
PRESS_NAME="Press_4"
SMB_SERVER=10.69.1.52
SMB_USER=ftp@maverickmolding.com
SMB_PASS=blueisland
SMB_DOMAIN=MAVERICKMOLDING
SMB_SHARE=Press_4
```

### USB Drive Size

Default is 2GB. To change, set before running installer:
```bash
export USB_SIZE_MB=4096  # 4GB
sudo ./install.sh
```

## Usage

### Check Status

```bash
# USB gadget status
systemctl status usb-gadget.service

# Sync timer status
systemctl status hmi-log-sync.timer

# View recent syncs
systemctl status hmi-log-sync.service
```

### View Logs

```bash
# Sync logs
journalctl -u hmi-log-sync.service -f

# Detailed sync logs
ls -la /var/log/hmi_log_sync/
tail -f /var/log/hmi_log_sync/sync_*.log
```

### Manual Sync

```bash
sudo /usr/local/bin/sync_logs.sh
```

### Re-run Auto-Configuration

```bash
sudo rm /etc/hmi_logger/.configured
sudo systemctl start hmi-auto-config.service
```

## Troubleshooting

### USB Drive Not Detected by HMI

1. Check if gadget module is loaded:
   ```bash
   lsmod | grep g_mass_storage
   ```

2. Check kernel messages:
   ```bash
   dmesg | grep -i gadget
   dmesg | grep -i dwc2
   ```

3. Verify USB gadget service:
   ```bash
   systemctl status usb-gadget.service
   ```

### SMB Connection Issues

1. Test network connectivity:
   ```bash
   ping 10.69.1.52
   ```

2. Test SMB access:
   ```bash
   smbclient -L //10.69.1.52 -U ftp@maverickmolding.com
   ```

3. Check credentials:
   ```bash
   cat /etc/hmi_logger/config
   ```

### Files Not Syncing

1. Check if files exist on USB:
   ```bash
   sudo /usr/local/bin/usb_gadget_mount.sh
   ls -la /mnt/usb_share/
   sudo /usr/local/bin/usb_gadget_unmount.sh
   ```

2. Check sync logs:
   ```bash
   cat /var/log/hmi_log_sync/sync_*.log | tail -50
   ```

## File Locations

| File | Purpose |
|------|---------|
| `/piusb.bin` | USB disk image (FAT32) |
| `/mnt/usb_share` | Mount point for USB image |
| `/mnt/smb_share` | Mount point for SMB share |
| `/etc/hmi_logger/config` | Runtime configuration |
| `/var/log/hmi_log_sync/` | Sync log files |
| `/usr/local/bin/sync_logs.sh` | Main sync script |
| `/usr/local/bin/auto_config.sh` | Auto-configuration script |

## Powering the Pi 4

Since the USB-C port is used for the USB gadget, you need alternative power:

1. **GPIO Header**: 5V to Pin 2 or 4, GND to Pin 6
2. **USB-C Y-Cable**: Data to HMI, power from USB charger
3. **PoE Hat**: If using Ethernet

## Differences from Pi Zero W

| Feature | Pi Zero W | Pi 4 |
|---------|-----------|------|
| USB Gadget Port | Micro USB (data port) | USB-C (power port) |
| USB Host Ports | None (same port) | 4x USB-A available |
| Power Requirement | Can be powered via data port | Needs separate power |
| Performance | Single-core, slower | Quad-core, faster syncs |

## License

MIT License
