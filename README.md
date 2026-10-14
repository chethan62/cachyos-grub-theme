# cachyos-pro — a GRUB boot menu you can verify without rebooting

A themed, upgrade-safe GRUB boot menu for a CachyOS + Windows 11 dual-boot, plus a harness that
renders the real menu in a throwaway QEMU boot so every layout claim below is a measurement rather
than an opinion.

![the boot menu](docs/screenshots/render-held.png)

**Status:** verified in QEMU/OVMF against the machine's real generated `grub.cfg`. It has **not been
photographed on the physical panel** — a reboot is the one step this repo cannot do for you.

## What it does

| | |
|---|---|
| **Menu** | Firmware entries are not mirrored into GRUB (`31_efi_bootnext` disabled), Windows is pinned by ESP UUID instead of os-prober, snapshot list filtered to the meaningful rows |
| **Theme** | Centred 760 px column, 40 px entry icons, 4 px teal accent highlight, countdown bar flush with the selected row |
| **Durability** | Every `/etc/grub.d` edit lives in `tools/grub-menu-patches` (apply/verify) and is re-applied after each `grub` upgrade by a pacman hook — a patch that no longer matches is reported, never silently dropped |

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
python3 tests/check.py          # assert the numbers in the table above
bash scripts/render-theme.sh    # boot it in QEMU and screenshot it (needs qemu + edk2-ovmf)
```

`tests/check.py` is the same script CI runs: it asserts the icon optical box, the geometry invariants
(the countdown bar is *derived* from `menu_left + item_padding`, `menu_width - 2*item_padding`, so an
edit that changes the padding without moving the bar fails), and that `grub-menu-patches` is
idempotent, complete, and loud about upstream text it can no longer find.

The render harness builds a standalone GRUB with an embedded menu that mirrors the real one, puts the
current theme on a 48 MB FAT image, and boots it under OVMF with the monitor socket as the control
channel — so the theme is exercised exactly as it renders on the machine, with no raw disk access.

## Install

```bash
sudo bash install/finish-theme.sh
```

Idempotent. It installs the theme, restores `GRUB_TIMEOUT`/`GRUB_GFXMODE` (a single GFXMODE with no
fallback drops to a text console), applies the `/etc/grub.d` patches, installs the pacman hook, and
regenerates `grub.cfg`.

**`install/` is this machine's configuration, not a generic installer** — `install/12_windows`
hardcodes the author's Windows ESP filesystem UUID (`F0E7-FD1E`) and `finish-theme.sh` writes to
`/etc/default/grub`. Change the UUID for your own disk (`lsblk -o NAME,FSTYPE,UUID`) before running it.

Revert:

```bash
sudo rm /etc/grub.d/12_windows /etc/grub.d/12_memtest
sudo cp /etc/default/grub.bak-theme /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

## Layout

| Path | What |
|---|---|
| `theme/theme.txt` | the theme, with the reasoning for each measured value in comments |
| `theme/build-assets.sh` | generates background, highlight slices, fonts and icons (idempotent) |
| `tools/grub-menu-patches` | all `/etc/grub.d` edits, `apply` or `verify`; `GRUB_D` overridable for tests |
| `scripts/render-theme.sh`, `scripts/test-grub.cfg` | the QEMU render harness |
| `install/` | this machine's installer, `12_windows`, `12_memtest`, and the pacman hook |
| `docs/` | research notes + the GRUB theme-format reference |
| `tests/check.py` | the checks CI runs |

## Gotchas (each cost a debugging session)

- **Styled-box PNGs must be RGBA** (`PNG32:`). GRUB decodes palette PNGs but ignores the `tRNS` chunk,
  so a palette+alpha slice renders fully opaque; grayscale and interlaced PNGs are rejected outright.
- **`grub-mkfont -n` sets the *family* name**, so GRUB looks up `Cantarell Regular 24 Regular 24`,
  misses, and silently falls back to Unifont. Omit `-n`; the derived name is the one to use.
- **The highlight is inset by `item_padding`**, so a bar aligned to the menu box sticks out ~16 px past
  the selected row. Align it to `box + padding` instead.
- **A missing `desktop-image` is fatal** (theme load aborts to a text menu); a missing box slice is
  silent; a typo in a global property aborts the theme while the same typo in a component is ignored.
- **A flat monochrome penguin is unrecognisable.** Tux reads as "penguin" because of its two-tone
  body; the flat version was tried, rendered, and reverted.
- **Right-aligning the submenu `▶` is impossible.** GRUB 2.16's theme format has no submenu-indicator
  property; the marker is part of the label string, so its x position drifts with the title length.

## Licensing

- **Code and theme: MIT** (see `LICENSE`).
- **Brand icons are not redistributed.** `build-assets.sh` reads `cachyos.png` and `linux.png` (Tux)
  from the *installed* stock CachyOS theme at build time; a machine without it still builds and simply
  shows no icon on those rows. The Windows, firmware and snapshot glyphs are drawn in this repo.
- **Fonts are read from the system** (Cantarell, OFL; DejaVu Sans, Bitstream Vera licence) and converted
  to GRUB `.pf2` at build time — no font binaries are committed here.
- The screenshots in `docs/screenshots/` are QEMU renders of this menu, including the two brand icons.
