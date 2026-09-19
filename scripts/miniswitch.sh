#!/usr/bin/busybox sh
# miniboot v2: sysinfo + boot menu (main/mini/other/custom/firmware/power).
# Plain POSIX sh + ANSI escapes. VGA console and serial safe.
. /detect-root.sh

ESC="$(printf '\033')"
tui_hide() { printf '\033[?25l'; }
tui_show() { printf '\033[?25h'; }
tui_clear() { printf '\033[2J\033[H'; }

# ---------- system info ----------
sysinfo() {
    CPU="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//;s/  */ /g' | cut -c1-48)"
    MEM="$(awk '/MemTotal/ {printf "%d MB", $2/1024}' /proc/meminfo 2>/dev/null)"
    KERN="$(uname -r 2>/dev/null)"
    DISKS=""
    for p in /proc/partitions; do :; done
    DISKS="$(awk 'NR>2 && ($4 ~ /^(sd[a-z]|vd[a-z]|nvme[0-9]n[0-9]|mmcblk[0-9])$/) {printf "%s %.0fG  ", $4, $3/1048576}' /proc/partitions 2>/dev/null)"
    GPU="$(lspci -n 2>/dev/null | awk '$2 ~ /^03/ {print $3}' | tr '\n' ' ')"
    [ -z "$GPU" ] && GPU="?"
    printf '\033[1;35m  miniSYSTEM  \033[0;90m%s  |  %s RAM  |  %s\033[0m\n' "$CPU" "$MEM" "$KERN"
    printf '\033[0;90m  disks: %s\033[0m\n' "$DISKS"
    printf '\033[0;90m  gpus:%s\033[0m\n' "$GPU"
}

# ---------- menu infra (sets MENU_TEXT) ----------
tui_menu() {
    _title="$1"; shift
    _n=0
    for _i in "$@"; do _n=$((_n + 1)); eval "_opt$_n=\"\$_i\""; done
    _sel="${TUI_DEFAULT:-1}"
    _tleft="$TUI_TIMEOUT"
    while :; do
        tui_clear
        sysinfo
        printf '\033[1;36m'
        echo "  +============================+"
        printf '   %-27s\n' "$_title"
        echo "  +============================+"
        printf '\033[0m'
        echo ""
        _i=1
        while [ $_i -le $_n ]; do
            eval "_t=\"\$_opt$_i\""
            if [ $_i -eq "$_sel" ]; then
                printf '   \033[7m> %-24s\033[0m\n' "$_t"
            else
                printf '     %-24s\n' "$_t"
            fi
            _i=$((_i + 1))
        done
        echo ""
        if [ -n "$_tleft" ]; then
            printf '   auto: option %s in %ss  (arrows/1-9/enter)\n' "$_sel" "$_tleft"
        else
            echo "   arrows + enter, or press 1-9"
        fi
        if [ -n "$_tleft" ]; then
            if tui_readkey 1; then :; else
                _tleft=$((_tleft - 1))
                if [ "$_tleft" -le 0 ]; then
                    eval "MENU_TEXT=\$_opt$_sel"
                    tui_show; return 0
                fi
                continue
            fi
        else
            tui_readkey "" || continue
        fi
        case $KEY in
            up) _sel=$((_sel - 1)); [ "$_sel" -lt 1 ] && _sel=$_n ;;
            down) _sel=$((_sel + 1)); [ "$_sel" -gt "$_n" ] && _sel=1 ;;
            enter) eval "MENU_TEXT=\$_opt$_sel"; tui_show; return 0 ;;
            [1-9]) if [ "$KEY" -le "$_n" ]; then eval "MENU_TEXT=\$_opt$KEY"; tui_show; return 0; fi ;;
        esac
        _tleft=""
    done
}

tui_readkey() {
    if [ -n "$1" ]; then
        IFS= read -s -r -n1 -t "$1" _k1 || return 1
    else
        IFS= read -s -r -n1 _k1 || return 1
    fi
    if [ "$_k1" = "$ESC" ]; then
        IFS= read -s -r -n2 -t 1 _k2 || { KEY=esc; return 0; }
        case $_k2 in
            '[A') KEY=up ;;
            '[B') KEY=down ;;
            *) KEY=other ;;
        esac
        return 0
    fi
    if [ -z "$_k1" ]; then KEY=enter; else KEY="$_k1"; fi
    return 0
}

# ---------- EFI helpers (need efivarfs) ----------
efi_mounted=""
efi_mount() {
    [ -n "$efi_mounted" ] && return 0
    [ -d /sys/firmware/efi ] || return 1
    mkdir -p /efivars
    mount -t efivarfs efivarfs /efivars 2>/dev/null || return 1
    efi_mounted=1
    return 0
}
EFIVAR_GUID="8be4df61-93ca-11d2-aa0d-00e098032b8c"
# write UINT32 LE attributes(7) + hex bytes (args like 01 00 ..) to an EFI var
efi_write() {
    _name="$1"; shift
    _f="/efivars/${_name}-${EFIVAR_GUID}"
    printf '\007\000\000\000' > "$_f" 2>/dev/null || return 1
    for _b in "$@"; do
        printf "\\$(printf '%03o' "$((16#$_b))")" >> "$_f" 2>/dev/null || return 1
    done
    return 0
}
efi_bootnext() {
    # $1 = 4-hex-digit boot number, e.g. 0001
    _n="$1"
    _hi="${_n%"${_n#??}"}"
    _lo="${_n#??}"
    efi_mount || { echo "  !! no EFI vars (BIOS boot?)"; return 1; }
    efi_write "BootNext" "$_lo" "$_hi" || { echo "  !! cannot write BootNext"; return 1; }
    return 0
}
efi_firmware() {
    efi_mount || { echo "  !! no EFI vars (BIOS boot?)"; sleep 3; return 1; }
    efi_write "OsIndications" 01 00 00 00 00 00 00 00 || { echo "  !! cannot set OsIndications"; sleep 3; return 1; }
    echo "  rebooting to firmware setup..."
    sleep 2
    reboot -f
}

# ---------- find which filesystem holds $SUBDIR (mini may live on /home!) ----------
find_subdir_root() {
    _want="$1"
    FOUND_DEV=""
    for d in /dev/vd* /dev/sd* /dev/nvme*n*p* /dev/mmcblk*p* /dev/xvd*; do
        [ -b "$d" ] || continue
        case $d in *by-uuid*|*by-label*|*by-partuuid*) continue ;; esac
        mkdir -p /scan
        if mount -o ro "$d" /scan 2>/dev/null; then
            if [ -x "/scan/$_want/sbin/init" ]; then
                umount /scan 2>/dev/null
                FOUND_DEV="$d"
                return 0
            fi
            umount /scan 2>/dev/null
        fi
    done
    return 1
}

# ---------- kexec a kernel+initrd with microcode packing ----------
kexec_boot() {
    # $1 = sysroot path, $2 = /boot/vmlinuz-XXX, $3 = root UUID, $4 = extra cmdline
    _sr="$1"; _k="$2"; _uuid="$3"; _extra="$4"
    _ver="${_k#/boot/vmlinuz-}"
    _parts=""
    [ -e "$_sr/boot/amd-ucode.img" ] && _parts="$_sr/boot/amd-ucode.img"
    [ -e "$_sr/boot/intel-ucode.img" ] && _parts="$_parts $_sr/boot/intel-ucode.img"
    if [ -e "$_sr/boot/initramfs-${_ver}.img" ]; then
        _img="$_sr/boot/initramfs-${_ver}.img"
    elif [ -e "$_sr/boot/initramfs-linux.img" ]; then
        _img="$_sr/boot/initramfs-linux.img"
    else
        echo "  !! no initramfs for $_k"
        return 1
    fi
    # shellcheck disable=SC2086
    cat $_parts "$_img" > /tmp/miniboot-initrd.img 2>/dev/null || return 1
    if kexec -l "$_sr$_k" --initrd=/tmp/miniboot-initrd.img \
        --command-line="root=UUID=$_uuid rw loglevel=3 quiet splash $_extra"; then
        echo "  jumping into $_k ..."
        umount /sysroot 2>/dev/null
        exec kexec -e
    fi
    return 1
}

# ---------- scan all disks for OTHER linux roots ----------
os_scan() {
    OS_LIST=""
    for d in /dev/vd* /dev/sd* /dev/nvme*n*p* /dev/mmcblk*p*; do
        [ -b "$d" ] || continue
        case $d in *by-uuid*|*by-label*|*by-partuuid*) continue ;; esac
        _u=$(dev_uuid "$d")
        [ -z "$_u" ] && continue
        [ "$_u" = "$ROOT_UUID" ] && continue
        mkdir -p /scan
        if mount -o ro "$d" /scan 2>/dev/null; then
            if ls /scan/boot/vmlinuz-* >/dev/null 2>&1; then
                _label="$(cat /scan/etc/hostname 2>/dev/null)"
                [ -z "$_label" ] && _label="$(dev_label "$d")"
                [ -z "$_label" ] && _label="$_u"
                _label="$(echo "$_label" | sed 's/ /_/g' | cut -c1-32)"
                OS_LIST="$OS_LIST ${_u}|${_label}"
            fi
            umount /scan 2>/dev/null
        fi
    done
}

# ---------- custom entries from ESP entries.conf ----------
load_custom() {
    CUSTOM_LIST=""
    [ -z "$ESP_UUID" ] && return 0
    mkdir -p /esp
    _dev=""
    for d in /dev/vd* /dev/sd* /dev/nvme*n*p*; do
        [ -b "$d" ] || continue
        _u=$(dev_uuid "$d")
        # vfat UUIDs are short form; compare case-insensitively by suffix
        case "$ESP_UUID" in
            *"$_u"*|*"$_u"*) _dev="$d"; break ;;
        esac
        _u2=$(echo "$_u" | tr 'a-z' 'A-Z')
        _e2=$(echo "$ESP_UUID" | tr 'a-z' 'A-Z')
        [ "$_u2" = "$_e2" ] && { _dev="$d"; break; }
    done
    [ -z "$_dev" ] && return 0
    mount -o ro "$_dev" /esp 2>/dev/null || return 0
    [ -f /esp/EFI/miniboot/entries.conf ] || return 0
    while IFS= read -r _line; do
        case $_line in ''|'#'*) continue ;; esac
        CUSTOM_LIST="$CUSTOM_LIST
$_line"
    done < /esp/EFI/miniboot/entries.conf
}

# ================= main flow =================
tui_hide
mkdir -p /sysroot
load_custom

while :; do
    TUI_TIMEOUT="$TIMEOUT"
    TUI_DEFAULT="$DEFAULT"
    _items="Main System (kexec):Mini System (rescue desktop):Other Systems:Firmware Setup:Reboot:Power Off"
    if [ -n "$CUSTOM_LIST" ]; then
        _cl=""
        _old="$IFS"; IFS='
'
        for _c in $CUSTOM_LIST; do
            [ -z "$_c" ] && continue
            _cl="$_cl:Custom: $(echo "$_c" | cut -d'|' -f2)"
        done
        IFS="$_old"
        _items="$_items$_cl"
    fi
    _old="$IFS"; IFS=':'
    # shellcheck disable=SC2086
    tui_menu "MINIBOOT - boot what?" $_items
    IFS="$_old"
    case $MENU_TEXT in
        *Mini*) GOTO=mini ;;
        *Other*) GOTO=other ;;
        *Firmware*) GOTO=firmware ;;
        *Reboot*) GOTO=reboot ;;
        *Power*) GOTO=poweroff ;;
        Custom:*) GOTO=custom ;;
        *) GOTO=main ;;
    esac

    if [ "$GOTO" = "mini" ]; then
        mkdir -p /sysroot
        if mount -o rw "$ROOT_DEV" /sysroot 2>/dev/null && [ -x "/sysroot/$SUBDIR/sbin/init" ]; then
            FOUND_DEV="$ROOT_DEV"
        else
            umount /sysroot 2>/dev/null
            echo "  not on main root, scanning disks..."
            if ! find_subdir_root "$SUBDIR"; then
                echo "  !! mini system not found on any disk"; sleep 2; continue
            fi
            if ! mount -o rw "$FOUND_DEV" /sysroot 2>/dev/null; then
                echo "  !! cannot mount $FOUND_DEV"; sleep 2; continue
            fi
        fi
        mount --bind "/sysroot/$SUBDIR" "/sysroot/$SUBDIR"
        echo "  entering miniboot desktop..."
        tui_show
        exec switch_root "/sysroot/$SUBDIR" /sbin/init
    fi

    if [ "$GOTO" = "firmware" ]; then efi_firmware; continue; fi
    if [ "$GOTO" = "reboot" ]; then tui_show; reboot -f; fi
    if [ "$GOTO" = "poweroff" ]; then tui_show; poweroff -f; fi

    if [ "$GOTO" = "custom" ]; then
        _name="${MENU_TEXT#Custom: }"
        _line="$(printf '%s\n' "$CUSTOM_LIST" | grep -F "|$_name|" | head -1)"
        _type="$(echo "$_line" | cut -d'|' -f1)"
        _a1="$(echo "$_line" | cut -d'|' -f3)"
        _a2="$(echo "$_line" | cut -d'|' -f4)"
        _a3="$(echo "$_line" | cut -d'|' -f5)"
        case $_type in
            efi) efi_bootnext "$_a1" && { echo "  booting $_name..."; sleep 2; reboot -f; }; sleep 3; continue ;;
            shell) tui_show; exec sh ;;
            reboot) tui_show; reboot -f ;;
            poweroff) tui_show; poweroff -f ;;
            kexec)
                mount -o ro "$ROOT_DEV" /sysroot 2>/dev/null || { echo "  !! mount failed"; sleep 2; continue; }
                kexec_boot /sysroot "$_a1" "$ROOT_UUID" "$_a2" || { echo "  !! kexec failed"; sleep 3; umount /sysroot 2>/dev/null; continue; } ;;
            *) echo "  !! unknown entry type $_type"; sleep 2; continue ;;
        esac
    fi

    if [ "$GOTO" = "other" ]; then
        os_scan
        if [ -z "$OS_LIST" ]; then
            echo "  no other bootable systems found."; sleep 2; continue
        fi
        _ol=""
        for _o in $OS_LIST; do
            _ol="$_ol:${_o#*|}"
        done
        _old="$IFS"; IFS=':'
        # shellcheck disable=SC2086
        tui_menu "Other systems" $_ol
        IFS="$_old"
        _uuid=""
        for _o in $OS_LIST; do
            [ "${_o#*|}" = "$MENU_TEXT" ] && _uuid="${_o%%|*}"
        done
        [ -z "$_uuid" ] && continue
        mkdir -p /sysroot
        _found=""
        for d in /dev/vd* /dev/sd* /dev/nvme*n*p*; do
            [ -b "$d" ] || continue
            _u=$(dev_uuid "$d")
            [ "$_u" = "$_uuid" ] && { _found="$d"; break; }
        done
        [ -z "$_found" ] && { echo "  !! device vanished"; sleep 2; continue; }
        mount -o ro "$_found" /sysroot 2>/dev/null || { echo "  !! mount failed"; sleep 2; continue; }
        _kl=""
        for k in /sysroot/boot/vmlinuz-*; do
            [ -e "$k" ] || continue
            _kl="$_kl:${k#/sysroot/boot/}"
        done
        _old="$IFS"; IFS=':'
        # shellcheck disable=SC2086
        tui_menu "Kernel on $MENU_TEXT" $_kl
        IFS="$_old"
        kexec_boot /sysroot "/boot/$MENU_TEXT" "$_uuid" "" || { echo "  !! kexec failed"; sleep 3; }
        umount /sysroot 2>/dev/null
        continue
    fi

    # ---- main: newest kernel on primary root ----
    if ! mount -o ro "$ROOT_DEV" /sysroot 2>/dev/null; then
        echo "  !! cannot mount root"; sleep 2; continue
    fi
    KLIST=""
    for k in /sysroot/boot/vmlinuz-*; do
        [ -e "$k" ] || continue
        KLIST="$KLIST ${k#/sysroot/boot/}"
    done
    if [ -z "$KLIST" ]; then
        echo "  !! no kernels"; sleep 2; umount /sysroot 2>/dev/null; continue
    fi
    TUI_TIMEOUT="$TIMEOUT"
    TUI_DEFAULT=1
    # shellcheck disable=SC2086
    tui_menu "Boot which kernel?" $KLIST
    kexec_boot /sysroot "/boot/$MENU_TEXT" "$ROOT_UUID" "$KEXTRA" || echo "  !! kexec failed"
    sleep 3
    umount /sysroot 2>/dev/null
done
