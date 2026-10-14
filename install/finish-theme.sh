#!/bin/bash
# Finish + verify the cachyos-pro GRUB theme.   Run:   sudo bash /home/chethan/.hermes/cache/scratch/finish-theme.sh
#
# Why it is needed: the agent's sudo credential stopped working mid-session, so these last
# root writes are handed over. IMPORTANT: /etc/default/grub currently has GRUB_TIMEOUT='-1'
# (left over from the capture runs) — step 1 puts it back to 3 seconds.
set -eu
S=/home/chethan/.hermes/cache/scratch
T=/usr/share/grub/themes/cachyos-pro
[ "$(id -u)" = 0 ] || { echo "run me with sudo"; exit 1; }

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
install -m755 "$S/grub-menu-patches" /usr/local/bin/grub-menu-patches
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
install -m755 "$S/12_memtest" /etc/grub.d/12_memtest
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
Exec = /bin/sh -c "chmod -x /etc/grub.d/31_efi_bootnext; /usr/local/bin/grub-menu-patches apply; grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1"
HOOK
echo "hook rewritten:"; grep -c "grub-menu-patches apply" /etc/pacman.d/hooks/31-efi-bootnext-off.hook
install -m755 "$S/build-assets.sh" "$T/build-assets.sh"
install -m644 "$S/theme.txt" "$T/theme.txt"
rm -f "$T"/cantarell_bold_40.pf2 "$T"/cantarell_bold_24.pf2 "$T"/cantarell_regular_17.pf2 "$T"/cantarell_regular_15.pf2 "$T"/terminal_box_*.png

echo "== 2/5 rebuild generated assets (background, highlight slices, fonts)"
"$T/build-assets.sh"

echo "== 3/5 regenerate grub.cfg"
grep -E "^GRUB_TIMEOUT=|^GRUB_GFXMODE=|^GRUB_THEME=|^GRUB_DISABLE_OS_PROBER=" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | grep -E "Found theme|error"
echo -n "effective: "; grep -m1 "set timeout=" /boot/grub/grub.cfg
grub-script-check /boot/grub/grub.cfg && echo "grub.cfg syntax OK"
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

echo "== 4/5 on-screen verification in QEMU (needs ~45 s; disk attached read-only)"
bash "$S/qemu-verify.sh"

echo "== 5/5 final state"
grep -m1 "set timeout=" /boot/grub/grub.cfg
ls "$T" | tr '\n' ' '; echo
echo "theme files: $(ls "$T" | wc -l)"
