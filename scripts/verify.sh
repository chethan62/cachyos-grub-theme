#!/bin/bash
# Every check this repo claims, in one command: build the assets, assert the measured numbers, audit
# the real menu generators, and render the theme in QEMU. The exit code is the number of failed
# stages, so this works by hand and in CI. Read-only except for the generated assets and ./render.
set +u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
LOG=$(mktemp -d); trap 'rm -rf "$LOG"' EXIT
fail=0
step() { printf '\n== %s\n' "$1"; }

step "assets"
if bash theme/build-assets.sh >"$LOG/build.log" 2>&1; then
  echo "  PASS  theme/build-assets.sh"
else
  echo "  FAIL  theme/build-assets.sh  ($LOG/build.log, kept below)"
  tail -5 "$LOG/build.log" | sed 's/^/        /'; trap - EXIT
  fail=$((fail + 1))
fi

step "measured numbers"
if python3 tests/check.py >"$LOG/check.log" 2>&1; then
  echo "  PASS  tests/check.py"
else
  echo "  FAIL  tests/check.py"; grep -E "^\s*(FAIL|not ok)" "$LOG/check.log" | head -5 | sed 's/^/        /'
  fail=$((fail + 1))
fi

step "installer logic"
if bash tests/test-detect-esp.sh >"$LOG/esp.log" 2>&1; then
  grep -q '^skip' "$LOG/esp.log" && echo "  SKIP  tests/test-detect-esp.sh ($(sed -n 's/^skip: //p' "$LOG/esp.log"))" \
    || echo "  PASS  tests/test-detect-esp.sh"
else
  echo "  FAIL  tests/test-detect-esp.sh"; grep FAIL "$LOG/esp.log" | head -3 | sed 's/^/        /'
  fail=$((fail + 1))
fi

step "menu generators (read-only, no root)"
if ! bash scripts/audit-menu.sh >"$LOG/audit.log" 2>&1; then
  echo "  FAIL  scripts/audit-menu.sh could not run"; fail=$((fail + 1))
elif grep -q "DUPLICATE:" "$LOG/audit.log"; then
  echo "  FAIL  duplicate menu entries:"
  grep "DUPLICATE:" "$LOG/audit.log" | sed 's/^ */        /'
  fail=$((fail + 1))
else
  echo "  PASS  scripts/audit-menu.sh (no duplicate entries)"
fi

step "render (QEMU/OVMF)"
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "  SKIP  qemu-system-x86_64 not installed"
elif ! ls /usr/share/edk2*/x64/OVMF_CODE*.fd >/dev/null 2>&1; then
  echo "  SKIP  OVMF firmware not installed"
elif bash scripts/render-theme.sh >"$LOG/render.log" 2>&1; then
  echo "  PASS  scripts/render-theme.sh -> $(ls -t render/render-*.png 2>/dev/null | head -1)"
else
  echo "  FAIL  scripts/render-theme.sh"; tail -5 "$LOG/render.log" | sed 's/^/        /'
  fail=$((fail + 1))
fi

[ "$fail" -eq 0 ] && echo && echo "all stages passed" || { echo; echo "$fail stage(s) failed"; }
exit "$fail"
