# Maintainer: winmastt
pkgname=miniboot
pkgver=0.2.0
pkgrel=1
pkgdesc="Tiny Linux TUI bootloader: kexec menu, OS detection, rescue-desktop switcher"
arch=('any')
url="https://github.com/winmastt/miniboot"
license=('MIT')
depends=('kexec-tools' 'busybox' 'efibootmgr' 'mkinitcpio')
optdepends=('plymouth: graphical menu (not implemented yet)')
install=miniboot.install
source=()
sha256sums=()

package() {
    cd "$srcdir/.."
    install -Dm755 hooks/miniswitch "$pkgdir/usr/lib/initcpio/install/miniswitch"
    install -Dm755 hooks/miniboot "$pkgdir/usr/lib/initcpio/install/miniboot"
    install -Dm755 scripts/miniswitch.sh "$pkgdir/usr/lib/miniboot/miniswitch.sh"
    install -Dm755 scripts/miniboot.sh "$pkgdir/usr/lib/miniboot/miniboot.sh"
    install -Dm755 scripts/detect-root.sh "$pkgdir/usr/lib/miniboot/detect-root.sh"
    install -Dm644 miniboot-switch.conf "$pkgdir/etc/mkinitcpio.d/miniboot-switch.conf"
    install -Dm644 miniboot.conf "$pkgdir/etc/mkinitcpio.d/miniboot.conf"
    install -Dm755 scripts/miniboot-refresh.sh "$pkgdir/usr/local/bin/miniboot-refresh.sh"
    install -Dm644 systemd/95-miniboot.hook "$pkgdir/etc/pacman.d/hooks/95-miniboot.hook"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
