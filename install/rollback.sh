#!/bin/bash
# Undo everything install/finish-theme.sh did.
#   sudo bash install/rollback.sh                    # dry run — prints the plan, changes nothing
#   sudo bash install/rollback.sh --apply            # stock menu back; custom theme left on disk
#   sudo bash install/rollback.sh --purge --apply    # also remove the theme + helper (uninstall)
#
# `install/finish-theme.sh --uninstall` is the same thing under the name people reach for. Note that
# finish-theme.sh with no arguments INSTALLS — an uninstall-by-default would be a footgun.
#
# Order matters: every guard runs BEFORE the first destructive step, so a bad invocation changes
# nothing at all. The regenerated grub.cfg is written to a temp file and syntax-checked before it
# replaces the live one — a half-written boot config is the one way this could leave you worse off.
set -eu
REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
T=/usr/share/grub/themes/cachyos-pro
HELPER=/usr/local/bin/grub-menu-patches
BACKUP=${GRUB_BACKUP:-/etc/default/grub.bak-theme}
STOCK_THEME=/usr/share/grub/themes/cachyos/theme.txt
APPLY=0; PURGE=0
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    --purge) PURGE=1 ;;
    *) echo "usage: rollback.sh [--apply] [--purge]  (finish-theme.sh --uninstall = --purge)" >&2; exit 2 ;;
  esac
done

# ---------- guards ----------
[ "$(id -u)" = 0 ] || { echo "run me with sudo"; exit 1; }
missing=0
for f in "$BACKUP" "$STOCK_THEME" /etc/default/grub; do
  [ -f "$f" ] || { echo "MISSING: $f"; missing=1; }
done
if [ "$missing" != 0 ]; then
  cat >&2 <<EOF

Refusing to touch anything. If the /etc/default/grub backup is gone, restore the theme line by hand:
  sudo sed -i "s|^GRUB_THEME=.*|GRUB_THEME='$STOCK_THEME'|" /etc/default/grub
  sudo grub-mkconfig -o /boot/grub/grub.cfg
  (then reboot; the stock theme is still installed at /usr/share/grub/themes/cachyos)
EOF
  exit 1
fi

show() { printf '  %s\n' "$*"; }
do_() { printf '  %s\n' "$*"; [ "$APPLY" = 1 ] && "$@"; return 0; }

regen() {  # never leave a broken boot config in place
  grub-mkconfig -o /tmp/grub.cfg.rollback.new >/dev/null
  if ! grub-script-check /tmp/grub.cfg.rollback.new; then
    echo "generated config failed its syntax check — the live grub.cfg was left untouched" >&2
    exit 1
  fi
  mv -f /tmp/grub.cfg.rollback.new /boot/grub/grub.cfg
}

echo "Rollback plan ($([ "$PURGE" = 1 ] && echo 'uninstall: theme + helper removed' || echo 'stock theme, custom theme kept')):"
echo "1. remove the entries and the upgrade hook this theme added"
do_ rm -f /etc/grub.d/12_windows /etc/grub.d/12_memtest
do_ rm -f /etc/pacman.d/hooks/31-efi-bootnext-off.hook
echo "2. restore /etc/default/grub from $BACKUP"
show "$BACKUP -> /etc/default/grub"; [ "$APPLY" = 1 ] && cp -f "$BACKUP" /etc/default/grub
echo "3. re-enable the firmware-entry script the installer disabled"
do_ chmod +x /etc/grub.d/31_efi_bootnext
echo "4. clear the saved default (otherwise the first entry stays unpredictable)"
do_ grub-editenv /boot/grub/grubenv unset saved_entry
echo "5. regenerate grub.cfg (temp file, syntax-checked, then swapped in)"
do_ regen
echo "6. remove the theme and its helper"
if [ "$PURGE" = 1 ]; then
  do_ rm -rf "$T"
  do_ rm -f "$HELPER"
  # the restored backup usually predates the theme, but if it still names the removed theme GRUB would
  # stop at "Press any key to continue..." with no menu — disable it and regenerate again.
  if sed -n 's/^GRUB_THEME=//p' /etc/default/grub | grep -q cachyos-pro; then
    do_ sed -i "s|^GRUB_THEME=.*|#GRUB_THEME= disabled (uninstalled)|" /etc/default/grub
    echo "   (GRUB_THEME pointed at the removed theme — disabled, regenerating again)"
    do_ regen
  fi
else
  show "(skipped — add --purge to remove $T and $HELPER)"
fi
echo
if [ "$PURGE" = 1 ]; then
  show "kept: /var/backups/cachyos-grub-theme/ and $BACKUP — the files that were replaced"
else
  show "kept: $T — harmless, and re-running install/finish-theme.sh reuses it"
fi
[ "$APPLY" = 1 ] && echo "Done — reboot to confirm." \
                 || echo "Dry run: nothing changed. Re-run with --apply to perform it."
