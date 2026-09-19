# MiniBoot — notes for future agents

Tiny Linux TUI bootloader (kexec menu + rescue-desktop switcher). BIOS-level
flow: EFI entry → stock Arch kernel + 6MB initramfs → `rdinit=/miniswitch.sh`
→ TUI → `kexec -e` into Main, or `switch_root` into Mini desktop.

## Live layout (this machine)

- Sources: `~/miniboot/` (scripts/, hooks/, *.conf, install.sh).
  Edit source, then rebuild — never edit deployed files directly.
- Deployed: `/usr/lib/miniboot/`, `/usr/lib/initcpio/install/miniboot*`,
  `/etc/mkinitcpio.d/miniboot*.conf`, `/boot/efi/EFI/miniboot/`.
- Rebuild + redeploy:
  `sudo mkinitcpio -c /etc/mkinitcpio.d/miniboot-switch.conf -k /boot/vmlinuz-linux -g /boot/miniboot-switch.img`
  then `sudo cp` the img to `/boot/efi/EFI/miniboot/`.
- Kernel updates auto-refresh via `/etc/pacman.d/hooks/95-miniboot.hook`.
- Home MiniBoot entry first in BootOrder; GRUB/rEFInd untouched behind it.

## Testing (QEMU, no reboot roulette)

- `qemu-system-x86_64 -enable-kvm -m 3G -smp 2 -kernel <vmlinuz> -initrd <img> \
  -append "rdinit=/miniswitch.sh miniboot.root=<UUID> ..." \
  -drive file=<disk>,format=raw,if=virtio -display none \
  -monitor stdio -serial file:<log>`
- Interact via monitor (`screendump /path/file.ppm`); read flow via serial log.
- OVMF firmware: `/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd` (+ copy of
  `OVMF_VARS.4m.fd`, never the original).
- **Fixtures MUST live in `~/miniboot-test/`, never `/tmp`** — the tmp cleaner
  wipes test disks mid-session. Fresh `mkfs` = new UUID: always re-read it
  with `blkid` and update the test cmdline.

## Shell pitfalls (all verified the hard way)

- busybox sh executes top-to-bottom: define functions **before** use in
  sourced files (`detect-root.sh` line-34 crash).
- Never parse blkid with bare `.*UUID=` — greedy match eats PARTUUID.
  Use `blkid -s UUID -o value` or the `dev_uuid`/`dev_label` helpers.
- `kexec --initrd` takes exactly ONE file: `cat microcode initramfs > bundle`.
- initramfs busybox lacks some applets (`tr` missing; `sed`/`awk` present).
  Verify contents with `sudo lsinitcpio` (images are root-only).
- `pkill -f <pattern>` matches your own shell cmdline — use PID files.
- Quote globs in bash tool calls (zsh `no matches found` aborts the line).
- `miniboot.root=` / `miniboot.timeout=` / `miniboot.default=` /
  `miniboot.esp=` / `miniboot.kextra=` are the supported cmdline knobs.

## Mini desktop notes

- Root at `/opt/miniboot-root` (same partition as main root, deliberate).
- GNOME 50 = Wayland-only: needs real DRM. QEMU virtual GPUs never bound
  here, so VM pixel tests of GNOME are unreliable — trust real-HW reports.
- Session starts from `/root/.bash_profile` (`exec gnome-session`); its
  output goes to the VGA console, NOT the journal.
- Root password is a sha512crypt hash in miniboot's shadow; the plaintext
  exists nowhere on disk. Never commit one.
- `mainboot` helper kexecs back into Main; SSH via enabled sshd + Tailscale.

## Repo conventions

- `install.sh` is idempotent and safe to re-run on the dev box.
- `www/` ships to GitHub Pages as-is (screenshots live in `www/img/`).
- No CI, tests, or lint — verification is the QEMU recipe above.
