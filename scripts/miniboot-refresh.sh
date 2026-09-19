#!/bin/sh
# Refresh MiniBoot ESP files (run after kernel updates).
set -e
mkinitcpio -c /etc/mkinitcpio.d/miniboot-switch.conf -k /boot/vmlinuz-linux -g /boot/miniboot-switch.img
cp /boot/vmlinuz-linux /boot/efi/EFI/miniboot/vmlinuz-linux
cp /boot/miniboot-switch.img /boot/efi/EFI/miniboot/miniboot-switch.img
