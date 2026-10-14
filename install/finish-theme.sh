#!/bin/bash
# Install / re-sync the cachyos-pro GRUB theme on this machine, then verify it.
#   sudo bash install/finish-theme.sh
#
# Idempotent: it installs the theme, restores the shipped GRUB_TIMEOUT + a GFXMODE fallback, applies
# the /etc/grub.d patches, installs the pacman hook that re-applies them after a grub upgrade, and
# regenerates grub.cfg — then renders the real disk in QEMU (read-only) to prove the result.
#
# Sources come from the repo this script lives in, so a fresh clone runs without editing paths.
set -eu
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
TH="$REPO/theme"; INST="$REPO/install"; TOOLS="$REPO/tools"; SCRIPTS="$REPO/scripts"
T=/usr/share/grub/themes/cachyos-pro
[ "$(id -u)" = 0 ] || { echo "run me with sudo"; exit 1; }

# --uninstall is the rollback script's --purge (it also removes the theme + helper). Same engine, so
# there is one place where the destructive steps and their guards live.
case "${1:-}" in
  --uninstall) shift; exec bash "$REPO/install/rollback.sh" --purge "$@" ;;
  --help|-h)
    cat <<'USAGE'
usage: finish-theme.sh                 install / re-sync the theme (the default action)
       finish-theme.sh --uninstall     remove everything it installed (dry run; add --apply)
       rollback.sh                     same, with --purge for the theme files
USAGE
    exit 0 ;;
esac

echo "== 1/5 restore the shipped timeout + a GFXMODE fallback, install final theme.txt + builder"
sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT='3'/" /etc/default/grub
# a single pinned mode has NO fallback: if the mode is absent GRUB drops to the text console.
# The manual says modes are tried in turn, so end the list with auto.
sed -i "s|^GRUB_GFXMODE=.*|GRUB_GFXMODE='1920x1080x32,1024x768,auto'|" /etc/default/grub
# snapshot menu titles: the default format carries snapper's free-text description and reaches
# 1438 px, which no reasonable menu width can fit. date+snapshot+type still identifies a snapshot
# and caps at 621 px (measured over all 100 real titles).
if grep -q '^GRUB_BTRFS_TITLE_FORMAT=' /etc/default/grub-btrfs/config; then
  sed -i 's|^GRUB_BTRFS_TITLE_FORMAT=.*|GRUB_BTRFS_TITLE_FORMAT=("date" "snapshot" "type")|' /etc/default/grub-btrfs/config
else
  printf '\nGRUB_BTRFS_TITLE_FORMAT=("date" "snapshot" "type")\n' >> /etc/default/grub-btrfs/config
fi
grep -E "^GRUB_BTRFS_TITLE_FORMAT" /etc/default/grub-btrfs/config
# '▶' on the two submenu rows: GRUB draws no submenu indicator and its theme format has no property
# for one (verified: the two submenu rows render exactly their label width, nothing more), so the
# marker has to live in the label text. The snapshots row has a knob; the Advanced row is hardcoded
# in 10_linux, so it is patched here and re-applied after grub upgrades by the pacman hook below.
if grep -q '^GRUB_BTRFS_SUBMENUNAME=' /etc/default/grub-btrfs/config; then
  sed -i 's|^GRUB_BTRFS_SUBMENUNAME=.*|GRUB_BTRFS_SUBMENUNAME="CachyOS Linux snapshots  ▶"|' /etc/default/grub-btrfs/config
else
  printf 'GRUB_BTRFS_SUBMENUNAME="CachyOS Linux snapshots  ▶"\n' >> /etc/default/grub-btrfs/config
fi
grep -E "^GRUB_BTRFS_SUBMENUNAME" /etc/default/grub-btrfs/config
# Every /etc/grub.d edit this menu needs lives in one script (one place to read, test, re-apply):
# the Advanced-row marker and the --class options that make the icons resolve.
install -m755 "$TOOLS/grub-menu-patches" /usr/local/bin/grub-menu-patches
/usr/local/bin/grub-menu-patches apply
# boot the last-used OS: GRUB_DEFAULT=saved + GRUB_SAVEDEFAULT=true is the supported pair
# (grub-mkconfig exports GRUB_SAVEDEFAULT; 00_header maps saved -> ${saved_entry})
sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/" /etc/default/grub
grep -q '^GRUB_SAVEDEFAULT=' /etc/default/grub \
  && sed -i "s/^GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/" /etc/default/grub \
  || printf "GRUB_SAVEDEFAULT=true\n" >> /etc/default/grub
grep -E "^GRUB_DEFAULT=|^GRUB_SAVEDEFAULT=" /etc/default/grub
# the snapshot submenu held 100 rows (50 pre + 50 post, x2 kernels). A post snapshot of the
# previous transaction is what the matching pre snapshot contained, so dropping "pre" halves the
# list without losing a rollback target, and the limit keeps the most recent 10.
for kv in 'GRUB_BTRFS_LIMIT="10"' 'GRUB_BTRFS_IGNORE_SNAPSHOT_TYPE=("pre")'; do
  k=${kv%%=*}
  if grep -q "^$k=" /etc/default/grub-btrfs/config; then
    sed -i "s|^$k=.*|$kv|" /etc/default/grub-btrfs/config
  else
    printf '%s\n' "$kv" >> /etc/default/grub-btrfs/config
  fi
done
grep -E "^GRUB_BTRFS_LIMIT|^GRUB_BTRFS_IGNORE_SNAPSHOT_TYPE" /etc/default/grub-btrfs/config
install -m755 "$INST/12_memtest" /etc/grub.d/12_memtest
# Windows entry: install it only when one is missing, so a local edit (a different ESP UUID) is never
# clobbered — and check the UUID it pins actually exists on a partition, because a stale UUID means a
# menu entry that cannot boot Windows.
if [ ! -f /etc/grub.d/12_windows ]; then
  install -m755 "$INST/12_windows" /etc/grub.d/12_windows
  echo "12_windows installed (check the ESP UUID matches this machine)"
elif cmp -s "$INST/12_windows" /etc/grub.d/12_windows; then
  echo "12_windows already current"
else
  # an older revision lacked the --class that lets the row resolve an icon. Back it up OUTSIDE
  # /etc/grub.d: a backup in there is itself a menu generator (grub-mkconfig runs every executable
  # file matching [0-9][0-9]_*, so "12_windows.bak" produced a SECOND "Windows 11" entry).
  mkdir -p /var/backups/cachyos-grub-theme
  cp -f /etc/grub.d/12_windows /var/backups/cachyos-grub-theme/12_windows.bak
  install -m755 "$INST/12_windows" /etc/grub.d/12_windows
  echo "12_windows refreshed (previous copy kept at /var/backups/cachyos-grub-theme/12_windows.bak)"
fi
# Migrate any backup an earlier revision left inside /etc/grub.d — each one is a duplicate entry.
for stray in /etc/grub.d/*.bak /etc/grub.d/*~ /etc/grub.d/*.old /etc/grub.d/*.orig /etc/grub.d/*.save; do
  [ -e "$stray" ] || continue
  case "$(basename "$stray")" in [0-9][0-9]_*) ;; *) continue ;; esac
  mkdir -p /var/backups/cachyos-grub-theme
  mv -f "$stray" "/var/backups/cachyos-grub-theme/$(basename "$stray")"
  echo "moved stray $(basename "$stray") out of /etc/grub.d — it was generating an extra menu entry"
done
# ESP UUIDs are XXXX-XXXX; match that shape rather than the text after the option, which is
# `--set=root` on the preceding token (a greedy match happily returns "--")
WIN_UUID=$(grep -oiE '[0-9a-f]{4}-[0-9a-f]{4}' /etc/grub.d/12_windows | head -1)
if [ -n "$WIN_UUID" ] && ! blkid -U "$WIN_UUID" >/dev/null 2>&1; then
  echo "WARNING: 12_windows pins ESP UUID $WIN_UUID, which no partition on this machine has" >&2
  echo "         (fix: lsblk -o NAME,FSTYPE,UUID | grep -i vfat)" >&2
fi
# every /etc/grub.d edit is on a package-owned file, so it is re-applied after every grub upgrade by
# the same hook that keeps 31_efi_bootnext disabled — the patches live in one script, not in here
cat > /etc/pacman.d/hooks/31-efi-bootnext-off.hook <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = grub

[Action]
Description = Re-disabling 31_efi_bootnext, re-applying the boot-menu patches, regenerating grub.cfg...
When = PostTransaction
Exec = /bin/sh -c "chmod -x /etc/grub.d/31_efi_bootnext; /usr/local/bin/grub-menu-patches apply; [ -f /usr/share/grub/themes/cachyos-pro/theme.txt ] || sed -i 's|^GRUB_THEME=.*|#GRUB_THEME= disabled (theme.txt missing)|' /etc/default/grub; grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1"
HOOK
echo "hook rewritten:"; grep -c "grub-menu-patches apply" /etc/pacman.d/hooks/31-efi-bootnext-off.hook
install -m755 "$TH/build-assets.sh" "$T/build-assets.sh"
install -m644 "$TH/theme.txt" "$T/theme.txt"
rm -f "$T"/cantarell_bold_40.pf2 "$T"/cantarell_bold_24.pf2 "$T"/cantarell_regular_17.pf2 "$T"/cantarell_regular_15.pf2 "$T"/terminal_box_*.png

echo "== 2/5 rebuild generated assets (background, highlight slices, fonts)"
"$T/build-assets.sh"

echo "== 3/5 regenerate grub.cfg"
# GRUB_THEME is set when the theme is really there, and UNSET when it is not. This is not cosmetic:
# a missing theme file is NOT a graceful fallback in GRUB 2.16 — it prints one error line and waits at
# "Press any key to continue..." with no menu at all (measured; see docs/screenshots/render-no-theme.png),
# which is a hang on a machine nobody is sitting at. With no theme set, GRUB draws its built-in menu
# with every entry listed (also measured — docs/screenshots/render-plain-menu.png).
if [ -f "$T/theme.txt" ]; then
  sed -i "s|^#\?GRUB_THEME=.*|GRUB_THEME='$T/theme.txt'|" /etc/default/grub
else
  echo "WARNING: $T/theme.txt is missing — disabling GRUB_THEME so GRUB falls back to its built-in menu" >&2
  sed -i "s|^GRUB_THEME=.*|#GRUB_THEME= disabled (theme.txt missing)|" /etc/default/grub
fi
grep -E "^#?GRUB_THEME=" /etc/default/grub
grep -E "^GRUB_TIMEOUT=|^GRUB_GFXMODE=|^GRUB_THEME=|^GRUB_DISABLE_OS_PROBER=" /etc/default/grub
# generate to a temp file and syntax-check BEFORE replacing the live config: a boot config that GRUB
# cannot parse is the one way this could leave the machine worse off than it found it.
grub-mkconfig -o /tmp/grub.cfg.new 2>&1 | grep -E "Found theme|error"
if grub-script-check /tmp/grub.cfg.new; then
  mv -f /tmp/grub.cfg.new /boot/grub/grub.cfg
  echo "grub.cfg syntax OK — installed"
else
  echo "generated grub.cfg FAILED its syntax check; the live config was left untouched" >&2
  exit 1
fi
# the snapshot submenu is the only place a label can overflow: the 760 px menu leaves 668 px of text
# room once the 40 px icon and its 20 px gutter are taken out of the row
echo -n "longest snapshot label after regeneration: "
grep -o "submenu '[^']*'" /boot/grub/grub-btrfs.cfg | sed "s/submenu '//; s/'$//" \
  | while IFS= read -r l; do magick -font /usr/share/fonts/cantarell/Cantarell-VF.otf -pointsize 24 label:"$l" -format "%w\n" info:; done \
  | sort -rn | head -1 | sed 's/$/ px  (must be <= 668 px)/'
# both submenu titles are emitted into grub.cfg (the inner per-snapshot titles live in
# grub-btrfs.cfg), so both markers must be grepped in grub.cfg
echo -n "submenu markers in the generated menu: "
printf "grub.cfg advanced=%s snapshots=%s\n" \
  "$(grep -c 'Advanced options for CachyOS Linux  ▶' /boot/grub/grub.cfg)" \
  "$(grep -c 'CachyOS Linux snapshots  ▶' /boot/grub/grub.cfg)"
# icons: a row shows an icon only if it carries a --class that resolves to a file in <themedir>/icons/
echo -n "entry classes in grub.cfg: "
grep -o -- '--class [a-z0-9-]*' /boot/grub/grub.cfg | awk '{print $2}' | sort | uniq -c \
  | awk '{printf "%s=%s ", $2, $1}'; echo
echo -n "icons in the theme: "
ls "$T"/icons/*.png 2>/dev/null | wc -l
# One optical box per icon: build-assets.sh trims each icon and fits it to 48 px on a 64 px canvas, so
# every trimmed box here should be ~48x48. The stock artwork ranges 32x32..56x44, which renders as
# visibly different icon sizes in one column — a swap that skips the normalise step shows up here.
for c in cachyos linux windows11 efi snapshots; do
  if [ -f "$T/icons/$c.png" ]; then
    printf "  %-10s %s\n" "$c" "$(magick "$T/icons/$c.png" -trim -format '%wx%h' info:)"
  else
    echo "  MISSING icon for --class $c"
  fi
done
echo -n "patch status: "; /usr/local/bin/grub-menu-patches verify || echo "  (a patch needs attention)"
# snapshot submenu size: inner titles are one per snapshot; expect <= 10 and no "pre" rows left
echo -n "snapshot rows after filtering: "
printf "%s submenus, %s pre-type left, memtest entry=%s\n" \
  "$(grep -c "^submenu '" /boot/grub/grub-btrfs.cfg)" \
  "$(grep -c '| pre ' /boot/grub/grub-btrfs.cfg)" \
  "$(grep -c 'Memory Test (memtest86+' /boot/grub/grub.cfg)"
# saved default must be wired
echo -n "saved-default wiring: "; grep -c 'saved_entry' /boot/grub/grub.cfg
sync

echo "== 4/5 on-screen verification in QEMU (real disk, read-only overlay)"
VERIFY_DIR="$REPO/.verify" bash "$SCRIPTS/qemu-verify.sh"

echo "== 5/5 final state"
grep -m1 "set timeout=" /boot/grub/grub.cfg
ls "$T" | tr '\n' ' '; echo
echo "theme files: $(ls "$T" | wc -l)"
# Does the installed theme match the sources just installed? An older run leaves a stale
# build-assets.sh behind; and the icons are re-encoded each build, so compare their geometry rather
# than their bytes (identical artwork can hash differently).
drift=0
for f in theme.txt build-assets.sh background.png; do
  cmp -s "$TH/$f" "$T/$f" || { echo "  DRIFT: $f differs from the source"; drift=1; }
done
for c in cachyos linux windows11 efi snapshots; do
  a=$(magick "$T/icons/$c.png" -trim -format '%wx%h' info: 2>/dev/null)
  b=$(magick "$TH/icons/$c.png" -trim -format '%wx%h' info: 2>/dev/null)
  [ "$a" = "$b" ] || { echo "  DRIFT: icon $c installed=$a source=$b"; drift=1; }
done
[ "$drift" = 0 ] && echo "installed theme matches the sources (theme.txt, builder, background, 5 icons)"
# grub.cfg is root-only, so this is the only place the generated menu can be inspected
printf "generated cfg: classes=[%s] markers adv/snap=%s/%s saved_entry refs=%s\n" \
  "$(grep -o -- '--class [a-z0-9-]*' /boot/grub/grub.cfg | awk '{print $2}' | sort -u | tr '\n' ' ')" \
  "$(grep -c 'Advanced options for CachyOS Linux  ▶' /boot/grub/grub.cfg)" \
  "$(grep -c 'CachyOS Linux snapshots  ▶' /boot/grub/grub.cfg)" \
  "$(grep -c 'saved_entry' /boot/grub/grub.cfg)"
# Every row that should show an icon needs BOTH its class in the generated config and its icon file in
# the theme. Only checkable here (grub.cfg is root-only), and it is the check that matters: a patch can
# land on a line that is never emitted, which is exactly how the snapshots row once lost its icon while
# `grub-menu-patches verify` still said ok.
echo "icon resolution:"
for pair in "CachyOS Linux:cachyos" "Advanced:linux" "Windows 11:windows11" "UEFI:efi" "snapshots:snapshots"; do
  row=${pair%%:*}; cls=${pair##*:}
  printf "  %-14s --class %-10s in cfg=%s  icon=%s\n" "$row" "$cls" \
    "$(grep -c -- "--class $cls" /boot/grub/grub.cfg)" \
    "$([ -f "$T/icons/$cls.png" ] && echo yes || echo MISSING)"
done
echo "duplicate-entry audit (grub-mkconfig runs every executable [0-9][0-9]_* file in /etc/grub.d):"
for f in /etc/grub.d/[0-9][0-9]_*; do
  case "$(basename "$f")" in
    *.bak|*~|*.old|*.orig|*.save|*.dpkg-*)
      echo "  STRAY $(basename "$f") — a backup in this directory generates its own menu entry";;
  esac
done
WIN_ENTRIES=0
for f in /etc/grub.d/[0-9][0-9]_*; do
  [ -x "$f" ] || continue
  WIN_ENTRIES=$((WIN_ENTRIES + $(bash "$f" 2>/dev/null | grep -c "menuentry 'Windows")))
done
echo "  Windows entries the generators produce: $WIN_ENTRIES (must be 1)"
echo "Reboot to see it on the panel — that is the one step this cannot do for you."
