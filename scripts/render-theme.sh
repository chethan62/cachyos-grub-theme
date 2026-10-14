#!/bin/bash
# Root-free GRUB theme render: standalone GRUB (embedded test cfg) on a FAT image carrying the current
# theme, booted under OVMF with KVM. No raw disk, no sudo, no reboot.
#   bash scripts/render-theme.sh                                   # scripts/test-grub.cfg
#   CFG=scripts/test-grub-no-theme.cfg bash scripts/render-theme.sh
#   screenshots land in ./render-*.png
#
# The theme is built from THIS REPO, and the run refuses to continue if that build fails or the theme
# did not reach the image: a harness that silently renders an empty theme produces confident nonsense —
# it did exactly that once, and the "errors on screen" it showed were its own, not GRUB's.
set -u
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
TH="$REPO/theme"
W=${WORK:-$PWD/render}; rm -rf "$W"; mkdir -p "$W/esp/EFI/BOOT"
rm -f "$W"/render-*.ppm "$W"/render-*.png

CFG=${CFG:-$REPO/scripts/test-grub.cfg}
[ -f "$CFG" ] || { echo "no config at $CFG"; exit 1; }
grub-mkstandalone -O x86_64-efi -o "$W/esp/EFI/BOOT/BOOTX64.EFI" \
  --modules="all_video gfxterm gfxmenu png fat search_fs_file normal echo test" \
  "boot/grub/grub.cfg=$CFG" 2>&1 | tail -1

# build the theme from the repo sources into a scratch dir (no root needed), then put that on the esp
# image — so the render always shows the CURRENT theme, not whatever is installed on this machine.
mkdir -p "$W/build/cachyos-pro"
cp -f "$TH/build-assets.sh" "$TH/theme.txt" "$W/build/cachyos-pro/" \
  || { echo "theme sources missing in $TH — nothing to render"; exit 1; }
bash "$W/build/cachyos-pro/build-assets.sh" >/dev/null \
  || { echo "theme build FAILED (see $W/build/cachyos-pro)"; exit 1; }
[ -f "$W/build/cachyos-pro/theme.txt" ] || { echo "theme build produced no theme.txt"; exit 1; }

dd if=/dev/zero of="$W/esp.img" bs=1M count=48 status=none
mformat -i "$W/esp.img" -F -v ESP ::
mmd -i "$W/esp.img" ::/EFI ::/EFI/BOOT ::/themes
mcopy -i "$W/esp.img" "$W/esp/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/
mcopy -s -i "$W/esp.img" "$W/build/cachyos-pro" ::/themes/
FILES=$(mdir -i "$W/esp.img" -b ::/themes/cachyos-pro | wc -l)
echo "esp: $(stat -c %s "$W/esp.img") bytes; theme files on image: $FILES; fonts built: $(ls "$W/build/cachyos-pro"/*.pf2 2>/dev/null | wc -l)"
[ "$FILES" -ge 10 ] || { echo "only $FILES theme files on the image — refusing to boot a broken image"; exit 1; }

MON=$W/qmon.sock; VARS=$W/OVMF_VARS.fd
rm -f "$MON"; cp -f /usr/share/edk2/x64/OVMF_VARS.4m.fd "$VARS"
ACCEL=tcg; [ -w /dev/kvm ] && ACCEL=kvm
QPID=""
cleanup() { [ -n "$QPID" ] && kill "$QPID" 2>/dev/null; }   # by PID: a -f pattern can hit the caller
trap cleanup EXIT

qemu-system-x86_64 -machine q35 -m 1024 -accel "$ACCEL" \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$W/esp.img",format=raw,if=none,id=esp \
  -device ide-hd,drive=esp \
  -device virtio-vga,xres=1920,yres=1080,edid=on \
  -display none -monitor unix:"$MON",server,nowait -serial file:"$W/serial.log" &
QPID=$!

python3 - "$MON" "$W" <<'PY'
import socket, sys, time
mon, W = sys.argv[1], sys.argv[2]
s = None
for _ in range(60):
    try:
        s = socket.socket(socket.AF_UNIX); s.connect(mon); break
    except OSError: time.sleep(0.5)
if s is None: sys.exit("monitor never came up")
def cmd(c, wait=0.5):
    s.sendall((c + "\n").encode()); time.sleep(wait)
def shot(n):
    cmd("screendump %s/render-%s.ppm" % (W, n), wait=1.4)
t0 = time.time()
def at(t):
    d = t0 + t - time.time()
    if d > 0: time.sleep(d)
at(4.5); shot("countdown")          # 8 s timeout -> bar part-filled, seconds counting
at(6.0)
for _ in range(3): cmd("sendkey shift", wait=0.25)   # hold the menu
at(7.4); shot("held")               # selection highlight, steady
at(8.4); shot("held2")
# open the snapshots submenu (5th entry) to prove the longest labels are not clipped
at(9.0)
for _ in range(4): cmd("sendkey down", wait=0.25)
cmd("sendkey ret", wait=1.6)
at(11.0); shot("submenu")
cmd("quit", wait=0.5); s.close()
PY
sleep 1; kill $QPID 2>/dev/null; QPID=""
for p in "$W"/render-*.ppm; do [ -f "$p" ] && magick "$p" "${p%.ppm}.png" && rm -f "$p"; done
for f in "$W"/render-*.png; do printf "%-26s %s\n" "$(basename "$f")" "$(magick identify -format '%wx%h' "$f")"; done
