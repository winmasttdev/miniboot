#!/bin/sh
# MiniBoot uninstaller. Removes the EFI entry, ESP files and package files.
# Your bootloader entries and systems are untouched. Run as root.
set -e
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
ESP="${ESP:-/boot/efi}"

NUM="$(efibootmgr 2>/dev/null | grep -i miniboot | sed -n 's/^Boot\([0-9A-F]*\).*/\1/p' | head -1)"
[ -n "$NUM" ] && efibootmgr -b "$NUM" -B && echo "removed EFI entry $NUM"
rm -rf "$ESP/EFI/miniboot" /boot/miniboot.img /boot/miniboot-switch.img
rm -f /usr/lib/initcpio/install/miniswitch /usr/lib/initcpio/install/miniboot
rm -rf /usr/lib/miniboot
rm -f /etc/mkinitcpio.d/miniboot-switch.conf /etc/mkinitcpio.d/miniboot.conf
rm -f /usr/local/bin/miniboot-refresh.sh /etc/pacman.d/hooks/95-miniboot.hook
echo "MiniBoot uninstalled. Your rescue root directory (if any) was left alone."
