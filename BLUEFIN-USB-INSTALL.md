# Installing Bluefin to a USB Drive

Install a persistent, bootable Bluefin system on a USB drive. This is not a live ISO — it's a full read-write installation that persists changes across reboots.

## Prerequisites

- A machine already running Bluefin (any variant)
- A USB drive (recommended 32 GB+)
- The USB device path (e.g. `/dev/sda`) — **double-check this before every command**

> **Note:** The USB device path can change between plugs (e.g. `/dev/sda` -> `/dev/sdb` -> `/dev/sdc`). Always run `lsblk` to confirm before proceeding.

## 1. Identify the USB device

Plug in the USB drive and find its device path:

```bash
lsblk
```

Look for the device matching your USB's size. In this guide we'll use `/dev/sda` — substitute your actual device.

> **Warning:** The install process will **wipe the entire target device**. Make sure you have the correct device.

## 2. Unmount existing partitions

If the USB has existing partitions or LUKS volumes mounted, unmount them first:

```bash
# Check what's mounted
lsblk /dev/sda

# Unmount any mounted partitions (adjust paths as needed)
sudo umount /dev/sda1
sudo umount /dev/sda2

# If there's an active LUKS volume, close it
sudo cryptsetup close <mapper-name>

# If the LUKS volume refuses to close, check what's using it:
sudo fuser -vm /dev/mapper/<mapper-name>
# Or force remove:
sudo dmsetup remove -f <mapper-name>
# If it still won't close, unplug and replug the USB — the stale mapping will be gone after replug
```

If your desktop auto-prompts to unlock the LUKS partition on plug-in, **cancel/dismiss** that prompt.

## 3. Find your current image

Check which image your system is running:

```bash
rpm-ostree status
```

Look for the image reference, e.g.:

```
ostree-image-signed:docker://ghcr.io/ublue-os/bluefin-dx:stable
```

## 4. Install to USB

### Option A: Without encryption

```bash
sudo podman run --rm --privileged --pid=host -v /dev:/dev -v /var/lib/containers:/var/lib/containers --security-opt label=disable ghcr.io/ublue-os/bluefin-dx:stable bootc install to-disk /dev/sda
```

### Option B: With LUKS encryption (recommended)

`bootc install to-disk` only supports `tpm2-luks` (bound to a specific machine), not passphrase-based LUKS. For a portable encrypted USB, manually set up partitions and LUKS first, then install with `bootc install to-existing-root`.

#### 4B.1. Partition the USB

```bash
sudo parted /dev/sda -- mklabel gpt
sudo parted /dev/sda -- mkpart EFI fat32 1MiB 513MiB
sudo parted /dev/sda -- set 1 esp on
sudo parted /dev/sda -- mkpart root 513MiB 100%
```

#### 4B.2. Format the EFI partition

```bash
sudo mkfs.fat -F32 /dev/sda1
```

#### 4B.3. Set up LUKS on the root partition

```bash
sudo cryptsetup luksFormat /dev/sda2
```

Type **`YES`** (all caps) when prompted, then enter and verify your passphrase.

#### 4B.4. Open, format, and mount

```bash
sudo cryptsetup open /dev/sda2 usb-root
sudo mkfs.xfs /dev/mapper/usb-root
sudo mount /dev/mapper/usb-root /mnt
sudo mkdir -p /mnt/boot/efi
sudo mount /dev/sda1 /mnt/boot/efi
```

#### 4B.5. Install Bluefin

```bash
sudo podman run --rm --privileged --pid=host -v /dev:/dev -v /mnt:/target -v /var/lib/containers:/var/lib/containers --security-opt label=disable ghcr.io/ublue-os/bluefin-dx:stable bootc install to-existing-root /target
```

#### 4B.6. Clean up

```bash
sudo umount /mnt/boot/efi
sudo umount /mnt
sudo cryptsetup close usb-root
```

> **Fish shell note:** Fish does not support `\` line continuation the same way bash does. Always paste podman commands as a **single line**.

## 5. Boot from the USB

1. Reboot and enter your BIOS/UEFI boot menu (usually F12, F2, or Del during POST)
2. Select the USB drive as the boot device
3. If you used LUKS, enter your passphrase at the prompt

## 6. Post-install setup

The USB installation is a fresh Bluefin system. On first boot you'll go through initial user setup. After that, you can use [z-bluefin-bootstrap](./README.md) to restore your full environment:

```bash
git clone https://github.com/juangalt/z-bluefin-bootstrap.git
cd z-bluefin-bootstrap
./z-bluefin-bootstrap.sh install all
```

## Troubleshooting

### "requires at least 1 arg(s)" from podman

The podman command is being split across lines incorrectly. Make sure the entire command is on one line (especially in fish shell).

### "Device usb-root already exists" / "Device or resource busy"

A stale LUKS mapping is lingering from a previous attempt. Try `sudo dmsetup remove -f usb-root`. If that fails, unplug and replug the USB — the stale mapping will be cleared. After replugging, re-check `lsblk` as the device name may change.

### USB not showing in boot menu

Some BIOS/UEFI implementations require Secure Boot to be disabled for non-signed bootloaders, or need USB boot explicitly enabled in settings.

### Slow performance

USB 3.0+ is strongly recommended. USB 2.0 drives will work but the system will feel sluggish. An NVMe-to-USB enclosure with a small NVMe drive gives the best portable experience.
