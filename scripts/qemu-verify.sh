#!/bin/bash
# End-to-end verification of the INSTALLED theme: boots the real disk read-only in QEMU (throwaway
# overlay, nothing is written to the disk) and screenshots the menu the machine would actually show.
#
#  Phase A (timeout=-1): menu held — proves the highlight renders and rows do not shift.
#  Phase B (timeout=3, the shipped value): captures the live countdown frames.
#
# Needs root: it changes GRUB_TIMEOUT twice to set up the two phases and regenerates grub.cfg, then
# reads the disk device. Verified frames land in $VERIFY_DIR (default ./.verify).
set -u
DISK=${DISK:-/dev/nvme0n1}
W=${VERIFY_DIR:-$(pwd)/.verify}; mkdir -p "$W"
MON=$W/qmon.sock; VARS=$W/OVMF_VARS.fd; LOG=$W/qemu-serial.log
[ -r "$DISK" ] || { echo "cannot read $DISK (run me with sudo, or set DISK=)"; exit 1; }
ACCEL=tcg; [ -w /dev/kvm ] && ACCEL=kvm
rm -f "$W"/ver-*.ppm "$W"/ver-*.png

QPID=""
cleanup() { [ -n "$QPID" ] && kill "$QPID" 2>/dev/null; }   # by PID: a -f pattern match can hit the caller's own shell
trap cleanup EXIT

set_timeout() {            # $1 = GRUB_TIMEOUT value
  sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT='$1'/" /etc/default/grub
  grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1
  sync
}
boot() {                   # $1 = python capture program
  rm -f "$MON" "$LOG"; cp -f /usr/share/edk2/x64/OVMF_VARS.4m.fd "$VARS"
  qemu-system-x86_64 -machine q35 -m 2048 -accel "$ACCEL" \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
    -drive if=pflash,format=raw,file="$VARS" \
    -drive file="$DISK",format=raw,if=none,id=d0,snapshot=on \
    -device nvme,drive=d0,serial=SN350 \
    -device virtio-vga,xres=1920,yres=1080,edid=on \
    -display none -monitor unix:"$MON",server,nowait -serial file:"$LOG" &
  QPID=$!
  python3 - "$MON" "$W" "$1" <<'PY'
import socket, sys, time
mon, W, phase = sys.argv[1], sys.argv[2], sys.argv[3]
s = None
for _ in range(60):
    try:
        s = socket.socket(socket.AF_UNIX); s.connect(mon); break
    except OSError: time.sleep(0.5)
if s is None: sys.exit("monitor never came up")
def cmd(c, wait=0.5):
    s.sendall((c + "\n").encode()); time.sleep(wait)
def shot(n):
    cmd("screendump %s/ver-%s.ppm" % (W, n), wait=1.4)
t0 = time.time()
def at(t):
    d = t0 + t - time.time()
    if d > 0: time.sleep(d)
if phase == "A":
    at(5.0);  shot("a-row1")
    at(6.4);  cmd("sendkey down")
    at(7.2);  shot("a-row2")
else:
    at(4.0);  shot("b-count1")
    at(4.7);  shot("b-count2")
    at(5.4);  shot("b-count3")
cmd("quit", wait=0.5)
s.close()
PY
  sleep 1; kill $QPID 2>/dev/null; QPID=""; sleep 0.5
  for p in "$W"/ver-*.ppm; do [ -f "$p" ] && magick "$p" "${p%.ppm}.png" && rm -f "$p"; done
}

echo "--- phase A: timeout=-1 (menu holds) ---"
set_timeout -1
boot A
echo "--- phase B: timeout=3 (shipped) ---"
set_timeout 3
boot B
echo "--- final config ---"
grep -E "^GRUB_TIMEOUT=|^GRUB_GFXMODE=" /etc/default/grub
grep -m1 "set timeout=" /boot/grub/grub.cfg
sync
for f in "$W"/ver-*.png; do printf "%-20s %s mean=%s\n" "$(basename "$f")" "$(magick identify -format '%wx%h' "$f")" "$(magick "$f" -resize 1x1! -depth 8 -format '%[pixel:p{0,0}]' info:)"; done
