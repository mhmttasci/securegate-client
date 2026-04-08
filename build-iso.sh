#!/bin/bash
set -e

apt-get update -qq
apt-get install -y live-build xorriso grub-efi-amd64-bin \
  mtools dosfstools squashfs-tools debootstrap debian-archive-keyring \
  2>&1 | tail -3

mkdir -p /lb && cd /lb

lb config \
  --distribution bookworm \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --bootloader grub-efi \
  --debian-installer none \
  --memtest none \
  --win32-loader false \
  --iso-volume "SECUREGATE" \
  --apt-recommends false \
  --mirror-bootstrap "http://deb.debian.org/debian/" \
  --mirror-chroot "http://deb.debian.org/debian/" \
  --mirror-binary "http://deb.debian.org/debian/"

mkdir -p config/package-lists
cat > config/package-lists/kiosk.list.chroot << 'EOF'
chromium
xorg
xserver-xorg
xserver-xorg-video-fbdev
xserver-xorg-video-vesa
xserver-xorg-input-evdev
openbox
fonts-dejavu
dbus
dbus-x11
x11-xserver-utils
xinit
procps
EOF

mkdir -p config/includes.chroot/etc/systemd/system/getty@tty1.service.d
mkdir -p config/includes.chroot/usr/local/bin
mkdir -p config/includes.chroot/app
mkdir -p config/includes.chroot/root

cp /work/index.html config/includes.chroot/app/index.html

# Girinti YOK — systemd bunu doğru okur
cat > config/includes.chroot/etc/systemd/system/getty@tty1.service.d/autologin.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF

cat > config/includes.chroot/root/.bash_profile << 'EOF'
if [ "$(tty)" = "/dev/tty1" ]; then
  exec /usr/local/bin/start-kiosk >> /tmp/kiosk.log 2>&1
fi
EOF

cat > config/includes.chroot/usr/local/bin/start-kiosk << 'EOF'
#!/bin/bash
export HOME=/root DISPLAY=:0
LOG=/tmp/kiosk.log
echo "" >> $LOG
echo "=== $(date '+%H:%M:%S') SecureGate ===" >> $LOG

pgrep -x dbus-daemon >/dev/null || dbus-daemon --system --fork 2>/dev/null || true
sleep 1

mkdir -p /etc/X11
cat > /etc/X11/xorg.conf << 'XCONF'
Section "Device"
  Identifier "Card0"
  Driver "fbdev"
EndSection
Section "Screen"
  Identifier "Screen0"
  Device "Card0"
  DefaultDepth 24
EndSection
XCONF

Xorg :0 vt1 -nocursor -nolisten tcp >> /tmp/xorg.log 2>&1 &
for i in $(seq 1 20); do
  DISPLAY=:0 xdpyinfo >/dev/null 2>&1 && break
  sleep 1
done

mkdir -p /root/.config/openbox
cat > /root/.config/openbox/rc.xml << 'OBXML'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config>
  <keyboard>
    <keybind key="A-F4"><action name="Nothing"/></keybind>
    <keybind key="A-Tab"><action name="Nothing"/></keybind>
    <keybind key="C-A-t"><action name="Nothing"/></keybind>
  </keyboard>
  <mouse><context name="Root"/></mouse>
  <applications>
    <application class="*">
      <decor>no</decor>
      <maximized>yes</maximized>
    </application>
  </applications>
</openbox_config>
OBXML

DISPLAY=:0 openbox &
sleep 2
DISPLAY=:0 xset s off 2>/dev/null || true
DISPLAY=:0 xset -dpms 2>/dev/null || true

DISPLAY=:0 chromium \
  --kiosk --no-sandbox --disable-infobars \
  --no-first-run --disable-gpu --in-process-gpu \
  --user-data-dir=/tmp/cr \
  "file:///app/index.html" >> $LOG 2>&1

sleep 3
exec "$0"
EOF
chmod 755 config/includes.chroot/usr/local/bin/start-kiosk

lb build 2>&1

ISO=$(find /lb -maxdepth 1 -name "*.iso" | head -1)
[ -z "$ISO" ] && { echo "ISO bulunamadı!"; ls -la /lb/; exit 1; }
cp "$ISO" /output/securegate-debian.iso
echo "TAMAM: $(du -sh /output/securegate-debian.iso)"
