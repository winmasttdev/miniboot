#!/usr/bin/busybox sh
# shared prologue: mounts API fs, parses cmdline, resolves ROOT_UUID -> $ROOT_DEV
# UUID/LABEL lookup that never confuses UUID with PARTUUID (greedy-sed trap)
dev_uuid() {
    blkid -s UUID -o value "$1" 2>/dev/null && return 0
    blkid "$1" 2>/dev/null | sed -n 's/.* UUID="\([^"]*\)".*/\1/p'
}
dev_label() {
    blkid -s LABEL -o value "$1" 2>/dev/null && return 0
    blkid "$1" 2>/dev/null | sed -n 's/.* LABEL="\([^"]*\)".*/\1/p'
}
ROOT_UUID="7219e5e5-5877-49a7-ad4f-5140a305a6a3"
SUBDIR="opt/miniboot-root"
TIMEOUT=""
DEFAULT="1"
KEXTRA=""
ESP_UUID=""
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sys /sys 2>/dev/null
mount -t devtmpfs dev /dev 2>/dev/null
for x in $(cat /proc/cmdline 2>/dev/null); do
    case $x in
        miniboot.root=*) ROOT_UUID="${x#*=}" ;;
        miniboot.subdir=*) SUBDIR="${x#*=}" ;;
        miniboot.timeout=*) TIMEOUT="${x#*=}" ;;
        miniboot.default=*) DEFAULT="${x#*=}" ;;
        miniboot.kextra=*) KEXTRA="${x#*=}" ;;
        miniboot.esp=*) ESP_UUID="${x#*=}" ;;
    esac
done
ROOT_DEV=""
i=0
while [ $i -lt 25 ]; do
    if [ -e "/dev/disk/by-uuid/$ROOT_UUID" ]; then
        ROOT_DEV="/dev/disk/by-uuid/$ROOT_UUID"
        break
    fi
    for d in /dev/vd* /dev/sd* /dev/nvme*n*p* /dev/mmcblk*p* /dev/xvd*; do
        [ -b "$d" ] || continue
        case $d in
            *by-uuid*|*by-label*|*by-partuuid*) continue ;;
        esac
        u=$(dev_uuid "$d")
        if [ "$u" = "$ROOT_UUID" ]; then ROOT_DEV="$d"; break; fi
    done
    [ -n "$ROOT_DEV" ] && break
    sleep 1
    i=$((i + 1))
done

