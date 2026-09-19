#!/bin/sh
# MiniBoot installer: TUI kexec bootloader + optional rescue-desktop switcher.
# Adds ONE EFI entry first in BootOrder. Existing entries untouched.
# Run as root. Optional env: ESP=/path KERNEL=/boot/vmlinuz-x ROOT_UUID=xxxx
#   MINIBOOT_SUBDIR=opt/miniboot-root
set -e
SRC="$(dirname "$(readlink -f "$0")")"
ESP="${ESP:-/boot/efi}"
KERNEL="${KERNEL:-/boot/vmlinuz-linux}"
SUBDIR="${MINIBOOT_SUBDIR:-opt/miniboot-root}"
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
for t in efibootmgr kexec mkinitcpio busybox; do
    command -v "$t" >/dev/null || { echo "need $t"; exit 1; }
done
[ -d /sys/firmware/efi ] || { echo "not an EFI boot"; exit 1; }
[ -f "$KERNEL" ] || { echo "kernel not found: $KERNEL"; exit 1; }

if [ -z "$ROOT_UUID" ]; then
    ROOT_UUID="$(findmnt -no UUID /)"
    echo "root UUID: $ROOT_UUID"
fi
ESP_UUID="$(blkid -s UUID -o value "$(findmnt -no SOURCE "$ESP")" 2>/dev/null)"
echo "ESP: $ESP ($ESP_UUID)"

install -Dm755 "$SRC/hooks/miniswitch" /usr/lib/initcpio/install/miniswitch
install -Dm755 "$SRC/hooks/miniboot" /usr/lib/initcpio/install/miniboot
install -Dm755 "$SRC/scripts/miniswitch.sh" /usr/lib/miniboot/miniswitch.sh
install -Dm755 "$SRC/scripts/miniboot.sh" /usr/lib/miniboot/miniboot.sh
install -Dm755 "$SRC/scripts/detect-root.sh" /usr/lib/miniboot/detect-root.sh
install -Dm644 "$SRC/miniboot-switch.conf" /etc/mkinitcpio.d/miniboot-switch.conf
install -Dm644 "$SRC/miniboot.conf" /etc/mkinitcpio.d/miniboot.conf
install -Dm755 "$SRC/scripts/miniboot-refresh.sh" /usr/local/bin/miniboot-refresh.sh
install -Dm644 "$SRC/systemd/95-miniboot.hook" /etc/pacman.d/hooks/95-miniboot.hook
sed -i "s|^SUBDIR=.*|SUBDIR=\"$SUBDIR\"|" /usr/lib/miniboot/detect-root.sh

mkinitcpio -c /etc/mkinitcpio.d/miniboot-switch.conf \
    -k "$KERNEL" -g /boot/miniboot-switch.img

mkdir -p "$ESP/EFI/miniboot"
cp "$KERNEL" "$ESP/EFI/miniboot/vmlinuz-linux"
cp /boot/miniboot-switch.img "$ESP/EFI/miniboot/miniboot-switch.img"

# entries.conf: harvested EFI entries + user template
{
    echo "# MiniBoot custom entries. Format: type|label|arg1|arg2|arg3"
    echo "#   efi|Label|NNNN      -> set BootNext NNNN and reboot"
    echo "#   kexec|Label|/boot/vmlinuz-x|extra-cmdline -> kexec from MAIN root"
    echo "#   shell|Label         -> rescue shell"
    echo "#   reboot|Label        -> reboot now"
    echo "#   poweroff|Label      -> power off"
    echo "# Labels must not contain ':' or '|'."
    echo "# Re-run install.sh to re-harvest (lines below MARKER survive)."
    echo "# --- harvested EFI entries ---"
    efibootmgr -v 2>/dev/null | grep -E '^Boot[0-9A-F]{4}' | while read -r line; do
        num="$(echo "$line" | sed -n 's/^Boot\([0-9A-F]*\).*/\1/p')"
        label="$(echo "$line" | sed -n 's/^Boot[0-9A-F]*[* ] \(.*\)\t.*/\1/p')"
        case $label in
            *MiniBoot*) continue ;;
            *) [ -n "$num" ] && [ -n "$label" ] && echo "efi|$label|$num" ;;
        esac
    done
    echo "# --- MARKER: your entries below ---"
    echo "#shell|Rescue shell"
} > "$ESP/EFI/miniboot/entries.conf"

DISK="$(findmnt -no SOURCE "$ESP" | sed 's/p\?[0-9]*$//')"
PART="$(findmnt -no SOURCE "$ESP" | grep -o '[0-9]*$')"
OLD="$(efibootmgr 2>/dev/null | grep -i miniboot | sed -n 's/^Boot\([0-9A-F]*\).*/\1/p' | head -1)"
[ -n "$OLD" ] && efibootmgr -b "$OLD" -B >/dev/null
efibootmgr -c -d "$DISK" -p "$PART" -L "MiniBoot" \
    -l /EFI/miniboot/vmlinuz-linux \
    -u "initrd=/EFI/miniboot/miniboot-switch.img rdinit=/miniswitch.sh miniboot.esp=$ESP_UUID quiet"
ALL="$(efibootmgr 2>/dev/null | grep -E '^Boot[0-9A-F]{4}' | sed -n 's/^Boot\([0-9A-F]*\).*/\1/p' | tr '\n' ',' | sed 's/,$//')"
NEW="$(efibootmgr 2>/dev/null | grep -i miniboot | sed -n 's/^Boot\([0-9A-F]*\).*/\1/p' | head -1)"
REST="$(echo "$ALL" | tr ',' '\n' | grep -v "^${NEW}$" | tr '\n' ',' | sed 's/,$//')"
efibootmgr -o "${NEW},${REST}" >/dev/null
echo "MiniBoot installed and first in BootOrder. Old entries kept as fallback."
if [ ! -x "/${SUBDIR}/sbin/init" ]; then
    echo "NOTE: no rescue root at /${SUBDIR} — the Mini option will report"
    echo "missing until you build one (pacstrap a minimal Arch there). Main/kexec path works regardless."
fi
