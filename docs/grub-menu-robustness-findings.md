# GRUB custom boot menu — robustness & security findings (Arch/CachyOS UEFI)

Every claim below is tied to a primary source URL. Verdicts reference the four
current choices. Unverified items are flagged explicitly at the end.

## 1. GRUB_DISABLE_OS_PROBER and the pinned Windows entry

- **What it actually is.** `GRUB_DISABLE_OS_PROBER` is a `grub-mkconfig` knob. The
  GNU GRUB manual states: *"It is disabled by default since automatic and silent
  execution of `os-prober`, and creating boot entries based on that data, is a
  potential attack vector. Set this option to 'false' to enable this feature."*
  → https://www.gnu.org/software/grub/manual/grub/html_node/Simple-configuration.html
  (Also quoted verbatim by Ask Ubuntu / Ubuntu MATE, but the manual is the source.)
- **CORRECTION on the CVE.** CVE-2024-2312 is **not** about os-prober. Its NVD
  description is: *"GRUB2 does not call the module fini functions on exit, leading
  to Debian/Ubuntu's peimage GRUB2 module leaving UEFI system table hooks after
  exit. This lead to a use-after-free condition, and could possibly lead to secure
  boot bypass."* CVSS 3.1 6.7 (Canonical), CWE-416 Use-After-Free.
  → https://nvd.nist.gov/vuln/detail/CVE-2024-2312
  → Canonical tracker: https://bugs.launchpad.net/ubuntu/+source/grub2-unsigned/+bug/2054127
  The os-prober default-off decision is a **hardening decision, not a CVE**; I found
  **no CVE assigned to os-prober/GRUB_DISABLE_OS_PROBER** (flag: unverified that any
  exists — searches returned none).
- **What breaks when enabled.** Enabling it (`=false` + installing `os-prober`) makes
  `grub-mkconfig` run `os-prober`, which mounts and inspects foreign filesystems as
  root. Arch documents the workflow and its prerequisites (FUSE3 for `grub-mount`,
  NTFS-3G caveat): → https://wiki.archlinux.org/title/GRUB ("Detecting other operating systems").
- **Pinning the Windows entry by ESP filesystem UUID instead.** `search --fs-uuid`
  sets `root` to the first device whose filesystem UUID matches; `chainloader` then
  loads from that root. → https://www.gnu.org/software/grub/manual/grub/html_node/search.html
  Arch's own chainload example uses exactly this form:
  `search --no-floppy --fs-uuid <UUID>` then `chainloader …`, and the generated
  os-prober entries additionally emit `--hint-*` and `$hints_string` for robustness.
  → https://wiki.archlinux.org/title/GRUB (Boot menu entry examples).
- **Failure mode if the ESP UUID ever changes.** `search --fs-uuid <old-uuid>` finds
  nothing → `root` is wrong/unset → `chainloader` fails ("file not found" / falls
  back to the GRUB prompt). This happens if the Windows ESP is recreated (Windows
  repair/reset, disk clone, `mkfs.vfat`), or the partition is reformatted. Windows
  reinstall/reset routinely rewrites its own ESP.
  **Recovery (no live USB required):** at the GRUB menu press `c`, then
  `search --fs-uuid --set=root <new-uuid>` → `chainloader /EFI/Microsoft/Boot/bootmgfw.efi` → `boot`;
  then boot Linux and re-run `grub-mkconfig` after editing the UUID in
  `/etc/grub.d/12_windows`. More robust long-term fix: search by **file** instead of
  UUID (`search --file --set=root /EFI/Microsoft/Boot/bootmgfw.efi`), which survives
  an ESP reformat as long as the path exists. → GNU GRUB manual `search` (URL above).
- **Verdict: LOW risk, idiomatic.** Disabling os-prober is the upstream/Arch default
  and strictly reduces attack surface. Pinning one Windows entry by ESP UUID is a
  reasonable trade; the only real cost is a manual recovery if the ESP is ever
  recreated. Switching the search criterion to `--file` removes even that.

## 2. GRUB_GFXMODE semantics

- **Manual.** *"you can only use modes which your graphics card supports via VESA
  BIOS Extensions (VBE), so for example native LCD panel resolutions may not be
  available. The default is 'auto'."* → https://www.gnu.org/software/grub/manual/grub/html_node/Simple-configuration.html
- **Fallback is explicit, not automatic.** `gfxmode`: *"The resolution may be
  specified as a sequence of one or more modes, separated by commas (',') or
  semicolons (';'); **each will be tried in turn until one is found**."*
  → https://www.gnu.org/software/grub/manual/grub/html_node/gfxmode.html
  So a **single** mode (`1920x1080x32`) has **no fallback**: if the firmware does not
  expose that mode via GOP/VBE, gfxterm init fails and GRUB continues in text/console
  mode — documented as `error: no suitable video mode found` / `no video mode
  activated`, after which the menu typically renders at a low mode (e.g. 640x480).
  → Ubuntu bug (real report): https://bugs.launchpad.net/ubuntu/+source/grub2/+bug/2012181
- **Recommended shape.** Arch explicitly recommends a list ending in `auto`:
  *"it is recommended that you edit the line to resemble
  `GRUB_GFXMODE=desired_resolution,fallback_such_as_1024x768,auto`."*
  → https://wiki.archlinux.org/title/GRUB/Tips_and_tricks (Setting the framebuffer resolution)
- **External 4K monitor on a dock.** Pinning `1920x1080x32` alone means: if the dock
  path does not offer 1080p (possible with differing firmware/GPU EDID handling), you
  lose the themed graphical menu and drop to the console — not "unreadable", but
  **unthemed and low-res**. If 1080p *is* offered on the 4K panel, GRUB renders at
  1080p — the theme's absolute-pixel layout does not scale, so it will look correct
  but upscaled. `auto` alone is also imperfect: it picks the *preferred* (usually
  native 4K) mode, which makes a small font tiny.
- **Verdict: MEDIUM risk — the only one of your four settings with a plausible boot
  regression.** Change to `GRUB_GFXMODE=1920x1080x32,1024x768,auto` (or
  `auto,1920x1080x32`) so a missing mode degrades gracefully instead of dropping the
  theme. If you care about the docked-4K case, either accept a tiny menu at native
  4K or generate a second, larger `.pf2` (see §5).

## 3. Theme/font file resolution when /boot is inside a btrfs subvolume

- **Theme value must be GRUB-readable at boot.** The manual for `GRUB_BACKGROUND`
  (same loading path as themes): *"The value of this option must be a file readable
  by GRUB at boot time."* → https://www.gnu.org/software/grub/manual/grub/html_node/Simple-configuration.html
- **grub-mkconfig rewrites paths relative to GRUB's root/prefix.** Arch: *"If you have
  installed GRUB on a separate partition, `/boot/grub/myimage` automatically becomes
  `/grub/myimage` in grub.cfg."* → https://wiki.archlinux.org/title/GRUB/Tips_and_tricks
  This is why the conventional, safe location for themes/fonts is
  `/boot/grub/themes/…` — same filesystem as the GRUB prefix.
- **Documented btrfs constraint.** *"GRUB's `grub-mkconfig` script does not respect
  Btrfs default subvolume settings… If `/` is not the top-level subvolume, it will
  always specify the corresponding `subvol` option, making it impossible to fall back
  by simply setting the default subvolume"* (upstream bug).
  → https://wiki.archlinux.org/title/Btrfs (Known issues) and
  → https://savannah.gnu.org/bugs/?66509 (upstream tracker, still open)
  The `(root)/@/boot/grub` form is documented in the encrypted-/boot example:
  `set prefix=($root)/@/boot/grub` — the `@` subvolume path is written **explicitly**
  because GRUB resolves from the filesystem root, not the mounted `/`.
  → https://wiki.archlinux.org/title/GRUB/Tips_and_tricks (Decrypt LUKS protected disk with the TPM)
- **If the theme file is unreadable at boot.** There is **no hard failure** — GRUB
  degrades: a missing styled-box slice "will simply be left empty"
  (→ https://www.gnu.org/software/grub/manual/grub/html_node/Theme-file-format.html),
  and a font that fails to load leaves the theme rendered in the default Unifont
  (normal `.pf2` fallback; the manual: fonts are loaded with `loadfont`, list with
  `lsfonts`). You get an ugly/default menu, not an unbootable system.
- **Verdict: MEDIUM risk, mostly cosmetic.** `GRUB_THEME` under `/usr/share/grub/themes/`
  only works if that path resolves for GRUB at boot on your subvolume layout. The
  idiomatic, low-risk location is `/boot/grub/themes/<name>/` (under the same
  filesystem GRUB reads as `$prefix`). If both `/usr/share` and `/boot` live in
  subvolumes of the same btrfs fs, it usually resolves — but this is layout-dependent
  and I could not find a primary source documenting GRUB's exact subvolume-path
  resolution for a plain `/usr/share/...` absolute path. **Flagged unverified.**

## 4. Secure Boot interactions

- **Module side-loading is prohibited (documented caveat).** Arch: *"Since GRUB
  version 2.06.r261.g2f4430cc0, loading modules in Secure Boot Mode via `insmod` is
  no longer allowed, as this would violate the expectation to not sideload arbitrary
  code. If the GRUB modules are not embedded in the EFI binary, and GRUB tries to
  sideload/`insmod` them, GRUB will fail to boot with the message:
  `error: prohibited by secure boot policy`."*
  → https://wiki.archlinux.org/title/GRUB (Secure Boot support → Shim-lock)
  Consequence: any module your theme/menu needs (e.g. `gfxterm`, `gfxmenu`, `png`,
  `jpeg`, `all_video`, `font`) must be **embedded in `grubx64.efi` at build time**
  (`grub-install --modules=…` / `grub-mkstandalone`).
- **Fonts are a signed artifact under Secure Boot.** GRUB *"has enforced
  verification of font files in secure boot mode"* (upstream changelog). A custom
  or even the stock `unicode.pf2` triggers `error: prohibited by secure boot policy`
  unless it is signed with a detached signature and the public key is embedded in the
  GRUB image. Real-world report + the exact upstream commit:
  → https://bbs.archlinux.org/viewtopic.php?id=282076
  → commit `93a786a00163e50c29f0394df198518617e1c9a5` (grub, "enforce … verification of font files")
  Practical signing path: embed a GnuPG pubkey (`grub-mkstandalone --pubkey boot.key`)
  and ship `font.pf2` + `font.pf2.sig`. `sbctl` cannot sign `.pf2` (not PE).
- **Theme PNGs/fonts are NOT signature-checked like modules.** The manual documents no
  signature requirement for theme images (only the font-file enforcement above). A
  theme that loads only **already-embedded** modules and a **signed/none** font is
  compatible with a signed chain. A custom unsigned font is the one theme element
  that can break it.
- **SBAT / shim.** If you boot via shim, `grubx64.efi` **must** carry an SBAT section
  (`--sbat /usr/share/grub/sbat.csv`) or shim refuses to launch it.
  → https://github.com/rhboot/shim/blob/main/SBAT.md
  → https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot
- **Binary outside the ESP is fine** — GRUB loads config/fonts/theme from the Linux
  filesystem (`/boot`), and Secure Boot validates the *loaded executable*
  (`grubx64.efi`), not the data files — **except** for the font-file enforcement above.
- **Verdict: only custom fonts interact with Secure Boot** (if it is enabled). Themes,
  PNGs, and ESP placement of `grubx64.efi` are fine. Verify with `bootctl` /
  `od … SecureBoot-…`. → https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot

## 5. gfxterm/gfxmenu font size and DPI

- **No documented maximum font size.** The GRUB manual specifies no `pf2`/gfxterm
  size cap. The only documented pixel limit is for background images: *"Image height
  and width will be restricted by an artificial limit of 16384."*
  → https://www.gnu.org/software/grub/manual/grub/html_node/Simple-configuration.html
- **Real-world data point (not authoritative).** A user scaling `pf2` fonts found
  ~96 pt rendered correctly and reported success up to ~500 pt; no upstream answer was
  given. → https://forum.manjaro.org/t/grub-pf2-max-size-limit/158135
- **Documented practical advice is to ship bigger pf2 fonts, not scale.** For 4K:
  Gentoo recommends `grub-mkfont -s 32 …` producing `terminus32b.pf2` and setting
  `GRUB_FONT`; Arch HiDPI likewise uses `grub-mkfont -s 30`.
  → https://wiki.gentoo.org/wiki/GRUB (HiDPI displays)
  → https://wiki.archlinux.org/title/HiDPI
  When `pf2` files sit in the theme directory, `grub-mkconfig` auto-loads every `*.pf2`
  there, so no extra wiring is needed.
- **Verdict: LOW risk.** No max-font-size limit is documented; if you target 1920x1080
  your current font is fine. Only add a larger `.pf2` if you actually boot at 4K
  (`auto` on a 4K panel) — and remember a large custom font is the §4 Secure Boot
  issue.

## Risk verdict summary

| Choice | Verdict | Why |
|---|---|---|
| os-prober disabled + pinned Windows entry (ESP fs-UUID) | **LOW — keep** | Upstream default, reduces attack surface; recovering from an ESP-UUID change is a 5-command GRUB-prompt fix; `search --file` removes the last fragility |
| `GRUB_GFXMODE=1920x1080x32` (single mode) | **MEDIUM — change** | No fallback for a single non-existent mode; use `1920x1080x32,1024x768,auto` |
| Theme files under `/usr/share` on btrfs subvolume | **MEDIUM — prefer `/boot/grub/themes`** | grub-mkconfig ignores btrfs default-subvolume; theme must be GRUB-readable at boot; failure is cosmetic (default menu), not unbootable |
| Custom fonts | **LOW (Secure Boot OFF) / MEDIUM (Secure Boot ON)** | Unsigned fonts are rejected under Secure Boot (`prohibited by secure boot policy`); sign with GnuPG or keep stock/signed |

## Could not verify

1. Whether GRUB resolves an absolute `/usr/share/grub/themes/...` path correctly
   across btrfs subvolumes — no primary source found; the safe, documented location is
   under GRUB's own prefix (`/boot/grub/themes`).
2. Any authoritative **maximum** gfxterm/pf2 font size (only forum anecdotes ~96–500 pt;
   the manual gives none).
3. Existence of any CVE tied to `os-prober`/`GRUB_DISABLE_OS_PROBER` — none found;
   CVE-2024-2312 is the unrelated peimage use-after-free.
4. The upstream GRUB commit page (`gitlab.com/git-mirrors/grub/-/commit/93a786a…`) and
   the Savannah commit were not directly fetchable (anti-bot / 422), so the font-verification
   claim rests on the Arch BBS report quoting the commit + the GRUB changelog text
   ("enforced verification of font files in secure boot mode"), not the raw diff.
