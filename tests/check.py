#!/usr/bin/env python3
"""Assert the numbers this repo's README claims, and the logic of grub-menu-patches.

    python3 tests/check.py

Run after theme/build-assets.sh. Stdlib only (uses ImageMagick, which the build already needs), so it
works on a fresh clone and in CI. Every check maps to a sentence in the README, so prose cannot drift
from the build.
"""
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
THEME = ROOT / "theme"
failures: list[str] = []


def check(ok: bool, label: str, detail: str = "") -> None:
    print(f"{'ok  ' if ok else 'FAIL'} {label}{'  ' + detail if detail else ''}")
    if not ok:
        failures.append(label)


def out(*cmd: str) -> str:
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def identify(path: pathlib.Path, fmt: str, trim: bool = False) -> str:
    """identify/convert exist in both ImageMagick 6 and 7 (the build shims `magick` for 6)."""
    if trim:
        return out("convert", str(path), "-trim", "-format", fmt, "info:")
    return out("identify", "-format", fmt, str(path))


def theme_props() -> dict:
    """Pull `key = value` pairs out of one component block of theme.txt."""
    text = (THEME / "theme.txt").read_text()
    blocks = {}
    current = None
    for line in text.splitlines():
        m = re.match(r"^\+\s+(\w+)\s*\{", line)
        if m:
            current = m.group(1)
            blocks.setdefault(current, [])
        elif current and re.match(r"^\}", line):
            current = None
        elif current:
            m = re.match(r'^\s*([\w-]+)\s*=\s*"?([^"#]+?)"?\s*$', line)
            if m:
                blocks[current].append((m.group(1), m.group(2)))
    return blocks


def main() -> int:
    print("== generated assets ==")
    menu = theme_props().get("boot_menu", [])
    if not menu:
        check(False, "theme.txt has a boot_menu block")
        return 1
    boot = dict(menu)

    if not (THEME / "background.png").exists():
        check(False, "background.png exists (run theme/build-assets.sh first)")
        return 1

    check(identify(THEME / "background.png", "%wx%h") == "1920x1080", "background is 1920x1080",
          identify(THEME / "background.png", "%wx%h"))
    # styled-box slices must stay RGBA: GRUB ignores tRNS, so a palette+alpha slice renders OPAQUE
    check("a" in identify(THEME / "select_c.png", "%[channels]"),
          "highlight slices carry an alpha channel", identify(THEME / "select_c.png", "%[channels]"))
    fonts = sorted(p.name for p in THEME.glob("*.pf2"))
    core = {"cantarell_bold_48.pf2", "cantarell_regular_24.pf2", "cantarell_regular_19.pf2",
            "dejavu_sans_15.pf2"}
    check(core <= set(fonts), "core fonts built (menu + hint faces)",
          f"{len(fonts)} pf2: {', '.join(fonts)}")
    # the 'c'-shell monospace face is copied from the stock CachyOS theme when present — optional
    print(f"     terminal font {'present' if 'terminus-18.pf2' in fonts else 'absent (shell falls back)'}")

    icons = sorted(p for p in (THEME / "icons").glob("*.png")) if (THEME / "icons").is_dir() else []
    check(len(icons) >= 3, "icons built", f"{len(icons)}: {', '.join(p.name for p in icons)}")
    boxes = {}
    for p in icons:
        box = identify(p, "%wx%h", trim=True)
        boxes[p.name] = box
    # the invariant: one optical box for the whole column (stock artwork spans 32x32..56x44)
    longest = {max(int(v.split("x")[0]), int(v.split("x")[1])) for v in boxes.values()}
    check(len(longest) == 1, "every icon shares one optical size",
          f"longest sides: {sorted(longest)} from {boxes}")

    print("\n== theme.txt geometry ==")
    # the countdown bar must stay flush with the SELECTED ROW, and GRUB insets the highlight by
    # item_padding — so the bar is derived, not independently chosen.
    pad = int(boot["item_padding"])
    bar = dict(theme_props().get("progress_bar", []))
    want_left, want_width = int(boot["left"]) + pad, int(boot["width"]) - 2 * pad
    check(int(bar["left"]) == want_left and int(bar["width"]) == want_width,
          "countdown bar matches the highlight extent (menu_left+padding, menu_width-2*padding)",
          f"bar={bar.get('left')}/{bar.get('width')} want={want_left}/{want_width}")
    check(boot["icon_width"] == boot["icon_height"] == "40", "icons are square at the themed size",
          f"{boot.get('icon_width')}x{boot.get('icon_height')}")
    # the icon gutter must leave the measured longest label room: 760 - 2*pad - icon - gutter
    room = int(boot["width"]) - 2 * pad - int(boot["icon_width"]) - int(boot["item_icon_space"])
    check(room >= 642, "text room covers the longest generated label (642 px measured)",
          f"{room} px available")

    print("\n== grub-menu-patches logic (against fixtures, not /etc/grub.d) ==")
    fixtures = {
        "10_linux": '    echo "submenu \'$(gettext_printf "Advanced options for %s" "${OS}" '
                    '| grub_quote)\' \\$menuentry_id_option \'gnulinux-advanced-$boot_device_id\' {"\n',
        "30_uefi-firmware": "\t\tmenuentry '$LABEL' \\$menuentry_id_option 'uefi-firmware' "
                            "${allowed_user_list}{\n",
        "41_snapshots-btrfs":
            # the real emission (line 629 of the upstream script) plus the stray an older revision of
            # this project left behind — the retired patch must undo exactly that
            "submenu '${submenuname}' ${protection_authorized_users}"
            "${unrestricted_access_submenu}{\n"
            "    entry \"submenu '${title_menu}' --class snapshots {\n",
    }
    tool = ROOT / "tools" / "grub-menu-patches"
    with tempfile.TemporaryDirectory() as td:
        for name, body in fixtures.items():
            (pathlib.Path(td) / name).write_text(body)
        env = {**os.environ, "GRUB_D": td}

        def run(mode: str) -> tuple[int, str]:
            r = subprocess.run([sys.executable, str(tool), mode], capture_output=True, text=True, env=env)
            return r.returncode, r.stdout

        # a class with no icon file renders nothing (GRUB walks an entry's classes in order and stops at
        # the first hit), so every class these scripts add must have an icon — this is the invariant
        # that a class on a never-emitted line hides, and it is why the Windows entry's FIRST class is
        # the one that has to exist
        classes = set(re.findall(r"--class ([a-z0-9-]+)",
                                 (ROOT / "tools" / "grub-menu-patches").read_text()))
        win = re.findall(r"--class ([a-z0-9-]+)", (ROOT / "install" / "12_windows").read_text())
        classes |= set(win[:1])
        # cachyos/linux are copied from the installed distro theme at build time, so a bare CI box has
        # no way to produce them; the four this repo draws must always be there.
        STOCK = {"cachyos", "linux"}
        missing_icons = sorted(c for c in classes
                               if c not in STOCK and not (THEME / "icons" / f"{c}.png").exists())
        absent_stock = sorted(c for c in classes & STOCK
                              if not (THEME / "icons" / f"{c}.png").exists())
        check(not missing_icons, "every --class the scripts add resolves to an icon file",
              f"missing: {missing_icons}" if missing_icons else f"{sorted(classes)}")
        if absent_stock:
            print(f"     (stock-drawn icons not on this machine: {absent_stock} — expected off-CachyOS)")

        rc, _ = run("verify")
        check(rc == 1, "verify reports the unpatched tree as incomplete")
        rc, txt = run("apply")
        check(rc == 0, "apply patches every pattern", txt.replace("\n", " | ")[:90])
        rc, txt = run("apply")
        check(rc == 0, "apply is idempotent (second run changes nothing)")
        # idempotency means exactly one marker, not several
        marker = (pathlib.Path(td) / "10_linux").read_text().count("--class linux")
        check(marker == 1, "no duplicated --class after two applies", f"{marker} occurrence(s)")
        rc, _ = run("verify")
        check(rc == 0, "verify reports the patched tree as complete")
        # and a tree whose upstream text moved must be reported, not silently passed
        (pathlib.Path(td) / "30_uefi-firmware").write_text("menuentry 'renamed upstream' {\n")
        rc, txt = run("verify")
        check(rc == 1 and "CHANGED" in txt, "drifted upstream text is reported, not passed")

        # the emitted row, not just the script: a class on the inner submenu line looks patched and
        # renders nothing, which is the bug this assertion exists to prevent
        snaps = (pathlib.Path(td) / "41_snapshots-btrfs").read_text()
        check("--class snapshots ${protection_authorized_users}" in snaps,
              "the class lands on the OUTER submenu row (the one the menu emits)")
        check("'${title_menu}' --class snapshots" not in snaps,
              "the stray class on the inner submenu is reverted")

    print()
    if failures:
        print(f"{len(failures)} check(s) failed: {'; '.join(failures)}")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
