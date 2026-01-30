# Pi 4 HMI Data Logger - Production Ready

Raspberry Pi 4 system for collecting HMI data logs via USB Mass Storage emulation with real-time SMB sync.

## Key Features

- **No HMI Disconnection**: USB connection remains active 24/7
- **Real-time Sync**: Files sync within 5 seconds of HMI write
- **1GB USB Drive**: Faster operations than 2GB/8GB images
- **Direct Folder Sync**: Files go straight to Press_N folder (no date subfolders)
- **Auto-Configuration**: Hostname-based setup (press7pi → Press_7)

## Hardware Requirements

- Raspberry Pi 4 (any RAM)
- 16GB+ microSD card
- USB-C cable to HMI
- Network connectivity

## Critical: USB-C Port Usage

Pi 4 acts as USB gadget through **USB-C power port only**:
- Power Pi via GPIO or special cable
- USB-C connects to HMI
- USB-A ports available for peripherals

## Quick Deploy (15 Pis)

### 1. Flash SD Card
```bash
# Flash Raspberry Pi OS Lite (64-bit)
# Enable SSH before first boot
```

### 2. Set Hostname
```bash
sudo hostnamectl set-hostname press3pi  # Press number: 3-8
```

### 3. Install
```bash
cd /opt
sudo git clone https://github.com/Moldingmaster/PI-4-data-collection.git
cd PI-4-data-collection
sudo chmod +x install.sh
sudo ./install.sh
sudo reboot
```

### 4. Verify
```bash
systemctl status usb-gadget.service
systemctl status hmi-realtime-sync.service
ls -lh /piusb.bin  # Should show 1.0G
```

### 5. Connect to HMI
Connect USB-C port to HMI. Files sync to: `\\10.69.1.52\HMI_Upload\Press_N\`

## Monitor
```bash
# Watch real-time sync
journalctl -u hmi-realtime-sync.service -f

# Check sync logs
ls -lht /var/log/hmi_log_sync/

# Verify files on SMB
sudo mount -t cifs //10.69.1.52/HMI_Upload /mnt/test -o 'username=ftp@maverickmolding.com,password=blueisland20!,vers=3.0'
ls -lh /mnt/test/Press_7/
sudo umount /mnt/test
```

## Configuration

Auto-configured from hostname:
- `press3pi` → Press_3 → `\\server\HMI_Upload\Press_3\`
- `press7pi` → Press_7 → `\\server\HMI_Upload\Press_7\`

Manual config: `/etc/hmi_logger/config`

## Troubleshooting
```bash
# Restart services
sudo systemctl restart usb-gadget.service
sudo systemctl restart hmi-realtime-sync.service

# Check USB gadget
lsmod | grep g_mass_storage

# Test SMB connectivity
smbclient -L //10.69.1.52 -U ftp@maverickmolding.com%blueisland20!
```

## Production Tested
✅ Press 7 - Fully tested and verified
