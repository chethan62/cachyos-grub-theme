#!/bin/bash
# Checks the installer's Windows-ESP detection without root or a real disk: the function is taken
# from install/finish-theme.sh as shipped, lsblk/blkid are stubbed, and mdir is redirected at two
# synthetic FAT images — one carrying Windows' loader at the real path, one not.
set +u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
for t in mdir mformat mmd mcopy; do
  command -v "$t" >/dev/null 2>&1 || { echo "skip: mtools not installed"; exit 0; }
done

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkimg() { # $1 = path, $2 = "with" | "without" loader
  dd if=/dev/zero of="$1" bs=1M count=8 status=none
  mformat -i "$1" :: || exit 1
  mmd -i "$1" ::/EFI ::/EFI/Microsoft ::/EFI/Microsoft/Boot || exit 1
  [ "$2" = with ] && { echo loader > "$TMP/l"; mcopy -i "$1" "$TMP/l" ::/EFI/Microsoft/Boot/bootmgfw.efi; }
  return 0
}
mkimg "$TMP/win.img" with
mkimg "$TMP/plain.img" without

eval "$(sed -n '/^detect_windows_esp()/,/^}/p' install/finish-theme.sh)"
[ "$(type -t detect_windows_esp)" = function ] || { echo "FAIL could not extract detect_windows_esp"; exit 1; }

run() { # $1 = image to point mdir at ; prints what the shipped function detects
  IMG=$1                                     # dynamic scoping: the stub below reads this
  lsblk() { echo "/dev/fake vfat"; echo "/dev/other ext4"; }
  blkid() { echo "AAAA-BBBB"; }
  # NB: "$1" here would be mdir's own first argument ("-i"), not run's — hence $IMG
  mdir() { command mdir -i "$IMG" "${@:3}"; }
  detect_windows_esp
  unset -f lsblk blkid mdir 2>/dev/null
}
fail=0
got=$(run "$TMP/win.img")
[ "$got" = "AAAA-BBBB" ] && echo "ok   ESP with \\EFI\\Microsoft\\Boot\\bootmgfw.efi is detected" \
  || { echo "FAIL with-loader image: got '$got'"; fail=1; }
got=$(run "$TMP/plain.img")
[ -z "$got" ] && echo "ok   vfat without Windows' loader is skipped" \
  || { echo "FAIL without-loader image: got '$got'"; fail=1; }
[ "$fail" = 0 ] && echo "detection test passed"
exit "$fail"
