# cachyos-pro — a GRUB boot menu you can verify without rebooting

[![license: MIT](https://img.shields.io/github/license/chethan62/cachyos-grub-theme)](LICENSE)

A themed, upgrade-safe GRUB boot menu for a CachyOS + Windows 11 dual-boot, plus a harness that
renders the real menu in a throwaway QEMU boot so every layout claim below is a measurement rather
than an opinion.

![the boot menu](docs/screenshots/render-held.png)

**Status:** verified in QEMU/OVMF against the machine's real generated `grub.cfg`, on the real disk and
on the theme's own objects. It has **not been photographed on the physical panel** — a reboot is the
one step this repo cannot do for you.

```bash
sudo bash install/finish-theme.sh     # install / re-sync (idempotent) · --uninstall to remove
python3 tests/check.py                # assert every number in the table below
```

**[Measured](#measured)** · [Verify it yourself](#verify-it-yourself) · [What the menu contains](#what-the-menu-contains) ·
[Install](#install) · [If the theme does not display](#if-the-theme-does-not-display) ·
[How to boot if the menu is unusable](#how-to-boot-if-the-menu-is-unusable) · [Requirements](#requirements) · [Layout](#layout) ·
[Gotchas](#gotchas) · [Licensing](#licensing)

## Measured

Environment: Lenovo Legion 82AU (1920x1080), CachyOS, GRUB 2.16, Cantarell 48/24/19 px.

| Claim | Measurement | How |
|---|---|---|
| Menu column | 760 x 400 px at x=580 (centre 960) | `theme/theme.txt`, confirmed in render |
| Icon optical box | all five icons max-dimension **30 px** at 1x | trimmed ink box per row in the render |
| Icon ink density | **47.0 – 62.0 %** (stock artwork: 40.2 – 85.2 %) | lit pixels / trimmed box |
| Countdown bar vs highlight | **+1 / −2 px** on each edge | teal fill + track extent vs the highlight's accent bar |
| Accent rule vs title descender | **14 px** clearance | title ink band vs rule band (0.3 em of the 48 px face) |
| Longest snapshot label | **642 px** in 668 px of text room | `magick label:` metrics over generated titles |
| Snapshot submenu | **100 → 20 rows** | `GRUB_BTRFS_LIMIT` + `IGNORE_SNAPSHOT_TYPE` replayed on the real 100 titles |
| Render iteration | ~15–45 s, no root, no reboot | `scripts/render-theme.sh` (standalone GRUB + FAT image + OVMF/KVM) |

## Verify it yourself

```bash
bash theme/build-assets.sh      # regenerate every asset from source
python3 tests/check.py          # assert the numbers above + the geometry invariants
bash scripts/render-theme.sh    # boot it in QEMU and screenshot it (needs qemu + edk2-ovmf)
```

`tests/check.py` is the same script CI runs: it asserts the icon optical box, the geometry invariants
(the countdown bar is *derived* from `menu_left + item_padding` and `menu_width - 2*item_padding`, so an
edit that changes the padding without moving the bar fails), and that `grub-menu-patches` is
idempotent, complete, and loud about upstream text it can no longer find.

The render harness builds a standalone GRUB with an embedded menu that mirrors the real one, puts the
current theme on a 48 MB FAT image, and boots it under OVMF with the monitor socket as the control
channel — the theme is exercised exactly as it renders on the machine, with no raw disk access.

## What the menu contains

Six top-level rows: `CachyOS Linux` · `Advanced options ▶` · `Windows 11` · `UEFI Firmware Settings` ·
`CachyOS Linux snapshots ▶`.

- **Advanced options** holds 4 rows — both kernels, each with a `(recovery mode)` twin. Those boot
  single-user and are a rescue path; remove them with `GRUB_DISABLE_RECOVERY='true'` if you prefer.
- **snapshots** is two levels deep: 10 snapshots (0 `pre` types — the filter works), each opening a
  kernel block with 2 rows. The 400 px menu box shows ~6 rows at a time and GRUB scrolls: the box
  cannot grow because the countdown sits directly under it. That is the deliberate trade — the
  alternative (countdown at the screen bottom) shows all 10 at once but detaches it from the menu.
- **Everything else emits nothing:** os-prober (disabled), `31_efi_bootnext` (non-executable, so no
  firmware-entry mirroring), xen/bli/fwupd/custom, and `12_memtest` (no payload installed).

`bash scripts/audit-menu.sh` prints this inventory for your own machine — read-only, no root.

## Install

<details>
<summary>what it changes · the expected output · from scratch · how to undo</summary>

```bash
sudo bash install/finish-theme.sh
```

Idempotent. It installs the theme, restores `GRUB_TIMEOUT`/`GRUB_GFXMODE` (a single GFXMODE with no
fallback drops to a text console), applies the `/etc/grub.d` patches, installs the pacman hook, and
regenerates `grub.cfg`.

**`install/` is this machine's configuration, not a generic installer** — `install/12_windows`
hardcodes the author's Windows ESP filesystem UUID (`F0E7-FD1E`) and `finish-theme.sh` writes to
`/etc/default/grub`. Change the UUID for your own disk (`lsblk -o NAME,FSTYPE,UUID`) before running it.

What a successful run looks like, in order:

```
== 1/5 ... 12_windows already current            (or "refreshed", or "moved stray …")
== 2/5 ... cachyos-pro assets rebuilt
== 3/5 ... GRUB_THEME='…/cachyos-pro/theme.txt'  grub.cfg syntax OK — installed
== 4/5 ... render-*.png frames (a refusal here means nothing was changed)
== 5/5 ... installed theme matches the sources   generated cfg: classes=[…] markers 1/1 saved_entry 4
          icon resolution      → 5 rows, all icon=yes
          duplicate-entry audit → Windows entries the generators produce: 1 (must be 1)
```

Any line reading `MISSING`, `STRAY`, `DRIFT`, `icon=MISSING`, or a count that is not `1` is a real
problem, and the line itself names the file to look at. Nothing is written to `grub.cfg` until the
generated config has passed `grub-script-check`.

**From scratch, on a different machine:**

```bash
git clone https://github.com/chethan62/cachyos-grub-theme && cd cachyos-grub-theme
lsblk -o NAME,FSTYPE,UUID | grep -i vfat     # find YOUR Windows ESP UUID
$EDITOR install/12_windows                   # put it in the fs-uuid line
sudo bash install/finish-theme.sh            # then reboot
```

The installer refuses to guess: if the UUID in `12_windows` is not on the machine it says so and tells
you how to list them. Anything it replaces is backed up to `/var/backups/cachyos-grub-theme/`.

**Undo — dry run first, then apply:**

```bash
sudo bash install/rollback.sh --apply                  # stock menu back; theme left on disk
sudo bash install/finish-theme.sh --uninstall --apply  # full uninstall: theme + helper removed
```

Both print the plan and change nothing until `--apply`. All guards run before the first destructive
step, so a missing backup refuses and leaves everything in place. `finish-theme.sh` with no arguments
**installs** — there is deliberately no uninstall-by-default.

</details>

## If the theme does not display

<details>
<summary>measured failure modes and their fixes</summary>

Both frames were rendered by `scripts/render-theme.sh` against an image the machine would boot from,
and are committed in `docs/screenshots/`:

| State | What actually happens |
|---|---|
| `GRUB_THEME` points at a **missing file** | One `error: file … not found` line and **"Press any key to continue…"** — **no menu, no entries at all** (`render-no-theme.png`). Modifier keys do not dismiss it (measured: three Shift presses left it unchanged); a real key does. On an unattended machine this **hangs the boot**. |
| **No `GRUB_THEME` at all** | GRUB's built-in menu with every entry listed, the first highlighted, and its countdown (`render-plain-menu.png`). This is the graceful state. |

So the installer — and the pacman hook after a grub upgrade — **unsets** `GRUB_THEME` when `theme.txt`
is missing, rather than leaving a config that stops at a prompt. Re-running the installer restores the
theme. Nothing here writes to the ESP or the firmware, so the firmware menu and its `EFI Hard Drive`
fallback are always still there.

| Symptom | Cause | Fix |
|---|---|---|
| Stops at `Press any key to continue…` | `GRUB_THEME` names a file that is not there | press a key, then re-run the installer (or point `GRUB_THEME` at the stock `/usr/share/grub/themes/cachyos/theme.txt`) |
| Plain menu, no theme, no error | theme not applied: a font name that does not resolve, or a typo in a *global* property | rebuild with `theme/build-assets.sh`; confirm font names with `grub-mkfont` (never `-n`); check `GRUB_THEME` |
| Icons missing, or uneven sizes on some rows | a `/etc/grub.d` patch lost (grub upgraded without the hook), or `grub.cfg` not regenerated | `grub-menu-patches verify`, then `sudo grub-mkconfig -o /boot/grub/grub.cfg` |
| A row appears twice | a backup file left inside `/etc/grub.d` — grub-mkconfig runs every executable `[0-9][0-9]_*` | the installer migrates them to `/var/backups/`; `tests/check.py` fails on any |
| Menu appears but the countdown never ends | `GRUB_TIMEOUT` is `-1` (the capture phases set that) | set `GRUB_TIMEOUT='3'` and regenerate |
| Boots a different entry than you expect | `GRUB_DEFAULT=saved` (last-used-OS) — **not usable on btrfs**, see the gotcha below | stay on `GRUB_DEFAULT=0`, which is what the installer sets here |
| Text console instead of the menu | `GRUB_GFXMODE` without a fallback list | keep the trailing `,1024x768,auto` |
| Want none of it | | `sudo bash install/rollback.sh --apply` |

</details>

## How to boot if the menu is unusable

<details>
<summary>five routes, in order of effort</summary>

In order of effort. On this machine's firmware (`efibootmgr`, 2026-10): `0002 CachyOS` →
`\EFI\cachyos\grubx64.efi` (that is GRUB again), `0003 Windows 11` → Windows' own loader, `0000 EFI
Hard Drive` → the fallback copy of GRUB. **Only the Windows entry bypasses GRUB**, so it is the one
firmware route that works when GRUB itself will not start.

1. **`Press any key to continue…`** → press Enter or space. GRUB then draws its built-in menu with
   every entry listed; boot normally from there.
2. **Plain/unthemed menu** → fully usable: ↑/↓ then Enter. Nothing to repair in order to boot.
3. **Only Windows is needed** → reboot, press **F12** (Legion boot menu), pick `Windows 11`.
4. **GRUB's `grub>` prompt** (what a config it cannot parse leaves you at) → boot CachyOS by hand.
   These UUIDs are this machine's: btrfs root `5bb50285-d467-4766-8a59-6d1eefe8df60` (subvol `@`, at
   the filesystem top level), Windows ESP `F0E7-FD1E`.

   ```
   search --no-floppy --fs-uuid --set=root 5bb50285-d467-4766-8a59-6d1eefe8df60
   linux /@/boot/vmlinuz-linux-cachyos root=UUID=5bb50285-d467-4766-8a59-6d1eefe8df60 rw rootflags=subvol=@ nowatchdog nvme_load=YES
   initrd /@/boot/initramfs-linux-cachyos.img
   boot
   ```

   (drop `splash loglevel=3` from the normal line so the boot is visible; use
   `vmlinuz-linux-cachyos-lts` + its initramfs if the main kernel is the problem.) Windows from the
   same prompt:

   ```
   search --no-floppy --fs-uuid --set=root F0E7-FD1E
   chainloader /EFI/Microsoft/Boot/bootmgfw.efi
   boot
   ```

5. **Live USB** — the only route that can *repair* the install:

   ```
   cachy-chroot                                  # on the CachyOS ISO: mounts root + ESP for you
   # by hand: mount -o subvol=@ /dev/nvme0n1p2 /mnt && mount /dev/nvme0n1p1 /mnt/boot/efi
   grub-mkconfig -o /boot/grub/grub.cfg
   ```

   To go back to the stock menu instead, `cp /etc/default/grub.bak-theme /etc/default/grub` first.

</details>

## Requirements

<details>
<summary>build and render dependencies</summary>

Building the assets needs `rsvg-convert` (librsvg2-bin), ImageMagick, `grub-mkfont` (grub-common) and
the Cantarell + DejaVu Sans fonts; the render harness additionally needs `qemu-system-x86_64`,
`edk2-ovmf` and `mtools`. Font paths are discovered across the Arch and Debian layouts, and the build
fails with a named missing dependency rather than emitting a theme with no fonts.

The `c`-shell monospace face is copied from the installed stock CachyOS theme when one is present;
where it is absent the shell falls back to whichever font loaded, and `tests/check.py` reports the
substitution as a note instead of a failure.

</details>

## Layout

<details>
<summary>what each file is for</summary>

| Path | What |
|---|---|
| `theme/theme.txt` | the theme, with the reasoning for each measured value in comments |
| `theme/build-assets.sh` | generates background, highlight slices, fonts and icons (idempotent) |
| `tools/grub-menu-patches` | all `/etc/grub.d` edits, `apply` or `verify`; `GRUB_D` overridable for tests |
| `scripts/render-theme.sh`, `scripts/test-grub.cfg` | the QEMU render harness (standalone GRUB on a FAT image, no disk access) |
| `scripts/render-theme.sh` with `CFG=scripts/test-grub-no-theme.cfg` | reproduces both theme-failure states above |
| `scripts/audit-menu.sh` | lists what every `/etc/grub.d` generator emits (read-only, no root) — submenus and duplicates included |
| `scripts/qemu-verify.sh` | end-to-end check of the **installed** theme: boots the real disk read-only and screenshots the menu |
| `install/` | this machine's installer, `rollback.sh`, `12_windows`, `12_memtest`, and the pacman hook |
| `docs/` | research notes + the GRUB theme-format reference |
| `tests/check.py` | the checks CI runs |

</details>

## Gotchas

<details>
<summary>lessons that each cost a debugging session</summary>

- **Styled-box PNGs must be RGBA** (`PNG32:`). GRUB decodes palette PNGs but ignores the `tRNS` chunk,
  so a palette+alpha slice renders fully opaque; grayscale and interlaced PNGs are rejected outright.
- **`grub-mkfont -n` sets the *family* name**, so GRUB looks up `Cantarell Regular 24 Regular 24`,
  misses, and silently falls back to Unifont. Omit `-n`; the derived name is the one to use.
- **The highlight is inset by `item_padding`**, so a bar aligned to the menu box sticks out ~16 px past
  the selected row. Align it to `box + padding` instead.
- **A missing `desktop-image` is fatal** — with `GRUB_THEME` set, GRUB stops at a keypress prompt with
  no menu rather than falling back. A missing box slice is silent; a typo in a global property aborts
  the theme while the same typo in a component is ignored.
- **A flat monochrome penguin is unrecognisable.** Tux reads as "penguin" because of its two-tone body;
  the flat version was drawn, rendered, and reverted.
- **A patch must target the line that is EMITTED, not the first line that looks right.** The snapshots
  row's `--class` was inserted into the inner per-snapshot submenu line (`${title_menu}`, inside
  `grub-btrfs.cfg`) instead of the outer row the menu shows (`${submenuname}`, line 629 of
  `41_snapshots-btrfs`) — so it verified "ok", rendered nothing, and only a render of the real disk
  caught it. Assert the generated output, not just the script.
- **A backup inside `/etc/grub.d` is a menu generator.** `12_windows.bak` matched grub-mkconfig's
  `[0-9][0-9]_*` glob and produced a second "Windows 11". Backups go to `/var/backups/`.
- **Generators need grub-mkconfig's own shell.** They use `grub_quote` from `grub-mkconfig_lib`; run as
  a child process they emit nothing, which looks exactly like "this generator has nothing to say".
- **Last-used-OS does not work when `/boot` is btrfs.** `GRUB_DEFAULT=saved` needs GRUB to *write*
  `grubenv`, and the btrfs driver cannot: the 1 KB env file lands as an inline extent with no block
  list, so `save_env` fails with "sparse file not allowed" and the boot halts at "Press any key to
  continue". The installer therefore forces `GRUB_DEFAULT=0` + `GRUB_SAVEDEFAULT=false` when
  `findmnt -T /boot/grub/grubenv` reports btrfs — the check is deliberate, not a leftover.
- **Right-aligning the submenu `▶` is impossible.** GRUB 2.16's theme format has no submenu-indicator
  property; the marker is part of the label string, so its x position drifts with the title length.

</details>

## Licensing

<details>
<summary>licences, borrowed icons, fonts</summary>

- **Code and theme: [MIT](LICENSE)** — the licence text is the verbatim MIT text, so the host detects
  it as MIT rather than `NOASSERTION`.
- **Brand icons are not redistributed.** `build-assets.sh` reads `cachyos.png` and `linux.png` (Tux)
  from the *installed* stock CachyOS theme at build time; a machine without it still builds and simply
  shows no icon on those rows. The Windows, firmware and snapshot glyphs are drawn in this repo.
- **Fonts are read from the system** (Cantarell, OFL; DejaVu Sans, Bitstream Vera licence) and converted
  to GRUB `.pf2` at build time — no font binaries are committed here.
- The screenshots in `docs/screenshots/` are QEMU renders of this menu, including the two brand icons.

</details>
