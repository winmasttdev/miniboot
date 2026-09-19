# MiniBoot

A tiny Linux bootloader with a real TUI: boots a minimal environment, shows
your hardware, finds your systems, and `kexec`s straight into them — or drops
into a rescue desktop. GRUB/rEFInd stay as fallback; MiniBoot only *adds* a
boot entry, it replaces nothing.

Inspired by ZFSBootMenu, minus the ZFS requirement. Works on any filesystem
you can mount from a minimal initramfs (ext4, btrfs, xfs...).

## Features

- Arrow-key TUI with live system details (CPU, RAM, disks, GPUs)
- Main System: kernel picker, microcode packing, `kexec` jump
- Mini System: `switch_root` into a rescue directory (any distro root works)
- Other Systems: auto-detects other Linux installs on all disks
- Custom entries (`entries.conf` on the ESP — edit from any OS)
- Reboot-to-firmware, reboot, poweroff
- Every failure drops to a rescue shell instead of hanging

## Install

```sh
git clone https://github.com/winmastt/miniboot && cd miniboot
sudo ./install.sh
```

Optional env: `ESP=/boot/efi KERNEL=/boot/vmlinuz-linux ROOT_UUID=xxxx`
`MINIBOOT_SUBDIR=opt/miniboot-root`.

`install.sh` will: install the mkinitcpio hooks + preset, build the image,
deploy kernel+image to `$ESP/EFI/miniboot/`, harvest your existing EFI
entries into `entries.conf`, create the `MiniBoot` EFI entry first in
BootOrder (old entries kept).

Requirements: Arch Linux (or derivative), `efibootmgr`, `kexec-tools`,
`busybox`, `mkinitcpio`, EFI system. Kernel needs `CONFIG_KEXEC=y`
(Arch default). Secure Boot must be off (or enroll your own keys).

## Rescue desktop (optional)

The Mini option needs a bootable directory, default `/opt/miniboot-root`
(a minimal Arch works: `pacstrap`, a WM/DE, `kexec-tools`, an autologin
getty). Without one, Mini reports missing and everything else still works.

## Uninstall

```sh
sudo ./uninstall.sh
```

Removes the EFI entry, ESP files and hooks. Rescue directory left alone.

## Files

- `scripts/miniswitch.sh` — the TUI (busybox-sh compatible)
- `scripts/miniboot.sh` — classic auto-boot variant
- `scripts/detect-root.sh` — shared device detection (PARTUUID-safe)
- `hooks/miniswitch`, `hooks/miniboot` — mkinitcpio install hooks
- `miniboot{-switch,}.conf` — minimal mkinitcpio configs
- `scripts/miniboot-refresh.sh` + `systemd/95-miniboot.hook` — rebuild on kernel updates

## Tested

QEMU/KVM end-to-end (serial logs + screenshots): menu render and navigation,
kernel auto-pick, microcode packing, `kexec -e` into target kernels,
switch-root to a GNOME desktop, custom BootNext entries, rescue shells.
Real AMD hardware: menu, sysinfo, kexec path confirmed.

## Kernel pinning (important)

MiniBoot boots its **own** kernel from the rescue root
(`/opt/miniboot-root/boot/vmlinuz-linux`), not the host's — kernel and
`/usr/lib/modules` must always match or nothing hardware-related loads
(no GPU, no WiFi, no vfat). `miniboot-refresh.sh` handles this; never copy
the host kernel over the ESP miniboot kernel.
