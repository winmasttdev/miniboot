#!/usr/bin/busybox sh
# miniboot: kexec boot menu. Finds kernels on the main root, jumps via kexec.
. /detect-root.sh
echo ""
echo "  == miniboot =="
if [ -z "$ROOT_DEV" ]; then
    echo "  !! root $ROOT_UUID not found, dropping to shell"
    exec sh
fi
mkdir -p /sysroot
if ! mount -o ro "$ROOT_DEV" /sysroot 2>/dev/null; then
    echo "  !! cannot mount root, dropping to shell"
    exec sh
fi
KERNLIST=""
for k in /sysroot/boot/vmlinuz-*; do
    [ -e "$k" ] || continue
    base="${k#/sysroot}"
    KERNLIST="$KERNLIST $base"
done
if [ -z "$KERNLIST" ]; then
    echo "  !! no kernels in /sysroot/boot, dropping to shell"
    exec sh
fi
echo "  kernels:"
n=0
for k in $KERNLIST; do
    n=$((n + 1))
    echo "    [$n] $k"
    eval "K$n=\"$k\""
done
echo ""
echo -n "  boot [1-$n, default 1 in ${TIMEOUT}s]: "
choice=""
if read -t "$TIMEOUT" choice 2>/dev/null; then
    :
else
    echo ""
    choice=1
fi
case $choice in
    ''|*[!0-9]*) choice=1 ;;
esac
[ "$choice" -lt 1 ] && choice=1
[ "$choice" -gt "$n" ] && choice=1
eval "SEL=\"\$K$choice\""
ver="${SEL#/boot/vmlinuz-}"
echo "  loading $SEL ..."
PARTS=""
if [ -e "/sysroot/boot/amd-ucode.img" ]; then
    PARTS="/sysroot/boot/amd-ucode.img"
fi
if [ -e "/sysroot/boot/initramfs-${ver}.img" ]; then
    IMG="/sysroot/boot/initramfs-${ver}.img"
elif [ -e "/sysroot/boot/initramfs-linux.img" ]; then
    IMG="/sysroot/boot/initramfs-linux.img"
else
    IMG=""
fi
if [ -z "$IMG" ]; then
    echo "  !! no initramfs found, dropping to shell"
    exec sh
fi
echo "  packing initramfs (microcode+image) ..."
# shellcheck disable=SC2086
cat $PARTS "$IMG" > /tmp/miniboot-initrd.img 2>/dev/null || {
    echo "  !! cannot pack initramfs, dropping to shell"
    exec sh
}
if kexec -l "/sysroot$SEL" --initrd=/tmp/miniboot-initrd.img \
    --command-line="root=UUID=$ROOT_UUID rw loglevel=3 quiet splash $KEXTRA"; then
    echo "  jumping..."
    umount /sysroot 2>/dev/null
    exec kexec -e
fi
echo "  !! kexec failed, dropping to shell"
exec sh
