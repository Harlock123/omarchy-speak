# Maintainer: Lonnie Watson <harlock123@gmail.com>
pkgname=omarchy-speak
pkgver=1.0.0
pkgrel=1
pkgdesc="Local neural text-to-speech for Omarchy: a speak command and a queueing daemon"
arch=('any')
url="https://github.com/harlock123/omarchy-speak"
license=('MIT')
depends=('bash' 'jq' 'curl' 'libpipewire' 'piper-tts')
optdepends=(
  'wl-clipboard: speak the current selection with SUPER+ALT+V'
  'libnotify: desktop notification when there is nothing to speak'
)
source=("$pkgname-$pkgver.tar.gz::$url/archive/v$pkgver.tar.gz")
sha256sums=('SKIP')

package() {
  cd "$srcdir/$pkgname-$pkgver"

  install -Dm755 -t "$pkgdir/usr/bin/" bin/speak bin/speakd bin/speak-selection bin/claude-speak-response
  install -Dm644 lib/speak-lib.sh "$pkgdir/usr/share/speak/lib.sh"

  # The unit is user-scoped: each user enables it with `systemctl --user enable --now speakd`.
  sed 's|@BINDIR@|/usr/bin|' systemd/speakd.service.in |
    install -Dm644 /dev/stdin "$pkgdir/usr/lib/systemd/user/speakd.service"

  install -Dm644 config/config.example "$pkgdir/usr/share/speak/config.example"
  install -Dm755 hooks/battery-low/speak-battery-low \
    "$pkgdir/usr/share/speak/hooks/battery-low/speak-battery-low"
  install -Dm755 install.sh "$pkgdir/usr/share/speak/setup.sh"
  install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
