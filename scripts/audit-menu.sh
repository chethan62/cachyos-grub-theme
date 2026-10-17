#!/bin/bash
# List what the boot menu will actually contain, by running each /etc/grub.d generator and summarising
# its output. Read-only, no root needed — the same technique that found a stray backup generating a
# second "Windows 11" entry. Use it to answer "what else is in there?" before rebooting.
#
# The generators use helpers (grub_quote, gettext_printf) that grub-mkconfig defines in its OWN shell,
# so they must be *sourced* here after sourcing the same library — executing them as child processes
# yields nothing, which looks exactly like "this generator emits nothing".
set +u
# no `set -u` here: grub-mkconfig_lib reads variables grub-mkconfig is expected to have set, and under
# -u it kills the shell mid-source — which looks exactly like "this script printed nothing".
. /usr/share/grub/grub-mkconfig_lib 2>/dev/null || { echo "grub-mkconfig_lib not found"; exit 1; }
pkgdatadir=${pkgdatadir:-/usr/share/grub}
# Export the helpers so both kinds of generator work: some need the library's functions (10_linux),
# others are self-contained (12_windows). Running all of them as children is one mechanism, not two.
export -f grub_quote gettext_printf 2>/dev/null
GRUB_DISTRIBUTOR=$(sed -n 's/^GRUB_DISTRIBUTOR="\?\([^"]*\)"\?.*/\1/p' /etc/default/grub | tail -1)
export GRUB_DISTRIBUTOR=${GRUB_DISTRIBUTOR:-CachyOS}
# ONE collection path, used by both the listing and the duplicate check. Two copies of this logic is
# how the duplicate check ended up seeing nothing: a re-implemented fallback blanked GRUB_DEVICE and
# emitted entries with empty titles. A generator is a child if it is self-contained (it inherits the
# exported helpers), otherwise it is sourced here so it can call the library's functions directly.
collect() {
  local out
  out=$( bash "$1" 2>/dev/null )
  if [ -z "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then
    out=$( . "$1" 2>/dev/null )
  fi
  printf '%s\n' "$out"
}
printf '%-22s %s\n' "GENERATOR" "EMITS"
for f in /etc/grub.d/[0-9][0-9]_*; do
  name=$(basename "$f")
  if [ ! -x "$f" ]; then
    printf '%-22s (not executable — skipped by grub-mkconfig)\n' "$name"
    continue
  fi
  # Two kinds of generator exist: self-contained ones that work as a child process, and ones that use
  # the library's helpers (which only exist in this shell). Try the child first, then fall back to
  # sourcing — a generator that legitimately emits nothing ('nothing' is also the correct answer for
  # 41_snapshots-btrfs, which writes grub-btrfs.cfg instead of stdout) simply stays empty.
  out=$( collect "$f" )
  entries=$(printf '%s\n' "$out" | grep -c "^[[:space:]]*menuentry ")
  subs=$(printf '%s\n' "$out"      | grep -c "^[[:space:]]*submenu ")
  if [ "$entries" = 0 ] && [ "$subs" = 0 ]; then
    printf '%-22s (nothing)\n' "$name"
    continue
  fi
  printf '%-22s %s menuentry, %s submenu\n' "$name" "$entries" "$subs"
  printf '%s\n' "$out" | grep -E "^[[:space:]]*(menuentry|submenu) " \
    | sed 's/^[[:space:]]*/    /' | cut -c1-108
done
echo
echo "snapshot submenu contents (/boot/grub/grub-btrfs.cfg, if readable):"
if [ -r /boot/grub/grub-btrfs.cfg ]; then
  printf '  snapshot submenus: %s\n' "$(grep -c "^submenu '" /boot/grub/grub-btrfs.cfg)"
  printf '  kernel rows:       %s\n' "$(grep -c "menuentry " /boot/grub/grub-btrfs.cfg)"
  printf '  pre-type rows:     %s  (0 = the IGNORE_SNAPSHOT_TYPE filter is working)\n' \
    "$(grep -c '| pre ' /boot/grub/grub-btrfs.cfg)"
else
  echo "  (grub-btrfs.cfg not readable here — check with sudo if needed)"
fi
echo
echo "duplicate check: any name appearing more than once in the whole menu?"
for f in /etc/grub.d/[0-9][0-9]_*; do
  [ -x "$f" ] || continue
  collect "$f"
done 2>/dev/null | grep -oE "menuentry '[^']+'" | sed "s/menuentry //" | sort | uniq -d | sed 's/^/  DUPLICATE: /'
echo "  (no output above = no duplicates)"
