#!/bin/sh
# Builds every generated asset of the cachyos-pro GRUB theme (idempotent).
# Needs: rsvg-convert, grub-mkfont, ImageMagick. Writes into its own directory.
set -eu
# ImageMagick 6 (Debian/Ubuntu, and therefore CI) has no `magick` binary, only `convert`.
command -v magick >/dev/null 2>&1 || magick() { convert "$@"; }
DIR=$(cd "$(dirname "$0")" && pwd)
VF=/usr/share/fonts/cantarell/Cantarell-VF.otf
DEJAVU=/usr/share/fonts/TTF/DejaVuSans.ttf
STAGE="$DIR/.stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"

# ---------- background 1920x1080 (vector -> PNG) ----------
cat > "$STAGE/bg.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="#0A0E17"/>
      <stop offset="0.55" stop-color="#0C1220"/>
      <stop offset="1" stop-color="#121A2B"/>
    </linearGradient>
    <radialGradient id="teal" cx="0.5" cy="0.34" r="0.62">
      <stop offset="0" stop-color="#07B9C7" stop-opacity="0.11"/>
      <stop offset="1" stop-color="#07B9C7" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="blue" cx="0.88" cy="0.94" r="0.55">
      <stop offset="0" stop-color="#4C6EF5" stop-opacity="0.08"/>
      <stop offset="1" stop-color="#4C6EF5" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="vig" cx="0.5" cy="0.5" r="0.78">
      <stop offset="0.55" stop-color="#000000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000000" stop-opacity="0.50"/>
    </radialGradient>
  </defs>
  <rect width="1920" height="1080" fill="url(#g)"/>
  <rect width="1920" height="1080" fill="url(#teal)"/>
  <rect width="1920" height="1080" fill="url(#blue)"/>
  <!-- accent rule, centred under the wordmark: x = 960 - 193/2. y=161 puts it 14 px below the title's
       descender (measured: Cantarell Bold 48 sets text y=100..147) — about 0.3 em of the 48 px face,
       the usual gap for a decorative rule under a wordmark. -->
  <rect x="863" y="161" width="193" height="3" rx="1.5" fill="#07B9C7" opacity="0.85"/>
  <rect width="1920" height="1080" fill="url(#vig)"/>
</svg>
SVG
rsvg-convert -w 1920 -h 1080 -o "$DIR/background.png" "$STAGE/bg.svg"

# ---------- selected-item highlight: one rounded panel -> 9 slices ----------
# GRUB's png module rejects indexed/palette PNGs (silently, leaving no highlight),
# so the slices are forced to 8-bit RGBA via the PNG32: writer.
cat > "$STAGE/hl.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="80" height="40" viewBox="0 0 80 40">
  <defs>
    <clipPath id="r"><rect x="0.5" y="0.5" width="79" height="39" rx="7.5" ry="7.5"/></clipPath>
  </defs>
  <rect x="0.5" y="0.5" width="79" height="39" rx="7.5" ry="7.5"
        fill="#07B9C7" fill-opacity="0.055" stroke="#FFFFFF" stroke-opacity="0.10" stroke-width="1"/>
  <!-- Left accent bar: GRUB stretches the highlight box to the whole menu width, so a filled pill
       always reads as an oversized empty bar. A 4 px bar over 60% of the panel's height renders as a
       bar ~60% of the row height (the highlight box measures ~60 px on a 56 px item), and vanishingly
       few themes scale the indicator to the row instead of filling it. -->
  <g clip-path="url(#r)"><rect x="0" y="8" width="4" height="24" fill="#07B9C7" fill-opacity="0.95"/></g>
</svg>
SVG
rsvg-convert -w 80 -h 40 -o "$STAGE/hl.png" "$STAGE/hl.svg"

slice() { # src prefix R W H
  src=$1; pfx=$2; r=$3; w=$4; h=$5
  magick "$src" -crop ${r}x${r}+0+0                   +repage -depth 8 PNG32:"$DIR/${pfx}_nw.png"
  magick "$src" -crop ${r}x${r}+$((w-r))+0            +repage -depth 8 PNG32:"$DIR/${pfx}_ne.png"
  magick "$src" -crop ${r}x${r}+0+$((h-r))            +repage -depth 8 PNG32:"$DIR/${pfx}_sw.png"
  magick "$src" -crop ${r}x${r}+$((w-r))+$((h-r))     +repage -depth 8 PNG32:"$DIR/${pfx}_se.png"
  magick "$src" -crop $((w-2*r))x${r}+${r}+0          +repage -depth 8 PNG32:"$DIR/${pfx}_n.png"
  magick "$src" -crop $((w-2*r))x${r}+${r}+$((h-r))   +repage -depth 8 PNG32:"$DIR/${pfx}_s.png"
  magick "$src" -crop ${r}x$((h-2*r))+0+${r}          +repage -depth 8 PNG32:"$DIR/${pfx}_w.png"
  magick "$src" -crop ${r}x$((h-2*r))+$((w-r))+${r}   +repage -depth 8 PNG32:"$DIR/${pfx}_e.png"
  magick "$src" -crop $((w-2*r))x$((h-2*r))+${r}+${r} +repage -depth 8 PNG32:"$DIR/${pfx}_c.png"
}
slice "$STAGE/hl.png" select 10 80 40

# ---------- entry icons ----------
# GRUB resolves <themedir>/icons/<class>.png (first matching class wins; missing = silent, no error),
# so a row only gets an icon if it carries a --class (see grub-menu-patches).
# Only the classes this menu uses are copied — the stock set is ~600 files of distro logos — and every
# one is normalised through the same pipeline: the raw artwork's ink box ranges from 32x32 (efi) to
# 56x44 (cachyos), which renders as five icons of plainly different size and weight in one column.
# Trim to the ink, fit the longest side to 48 px, centre on a 64x64 canvas => one optical box for all.
mkdir -p "$DIR/icons"
# windows11.png in the stock set is a SOLID block (85% ink) while every other icon is an outline
# (40-50%), so the mark is redrawn as an outline in the same stroke as the rest of the column (4 px,
# to land in the same ink-density band as the clock/Tux rather than reading as a heavy block).
cat > "$STAGE/windows11.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
  <g fill="none" stroke="#FFFFFF" stroke-width="4" stroke-linejoin="round">
    <rect x="11" y="11" width="17" height="17"/>
    <rect x="36" y="11" width="17" height="17"/>
    <rect x="11" y="36" width="17" height="17"/>
    <rect x="36" y="36" width="17" height="17"/>
  </g>
</svg>
SVG
# efi.png (a solid cog, 68% ink) is the last dense outlier in the column, so the firmware entry gets a
# drawn chip outline instead — same meaning, same stroke as the drawn clock.
cat > "$STAGE/efi.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
  <g fill="none" stroke="#FFFFFF" stroke-width="4" stroke-linejoin="round" stroke-linecap="round">
    <rect x="19" y="19" width="26" height="26" rx="4"/>
    <rect x="28" y="28" width="8" height="8"/>
    <path d="M26 19 L26 11"/><path d="M32 19 L32 11"/><path d="M38 19 L38 11"/>
    <path d="M26 45 L26 53"/><path d="M32 45 L32 53"/><path d="M38 45 L38 53"/>
    <path d="M19 26 L11 26"/><path d="M19 32 L11 32"/><path d="M19 38 L11 38"/>
    <path d="M45 26 L53 26"/><path d="M45 32 L53 32"/><path d="M45 38 L53 38"/>
  </g>
</svg>
SVG
# the set has no snapshot glyph at all, and restart.png reads as "reboot" rather than "restore"
cat > "$STAGE/snapshots.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
  <g fill="none" stroke="#FFFFFF" stroke-width="5" stroke-linecap="round">
    <circle cx="32" cy="32" r="20.5"/>
    <path d="M32 32 L32 19"/>
    <path d="M32 32 L42 38"/>
  </g>
</svg>
SVG
# linux.png stays the STOCK Tux: a flat monochrome penguin is unrecognisable (verified — a hand-drawn
# outline version at 30 px reads as an anonymous blob). Tux's identity is its two-tone body, so the
# shading is a deliberate trade for recognisability; the optical-size pass below still applies to it.
# The two brand marks come from the *installed* stock CachyOS theme rather than being redistributed
# here; a machine without it still builds (the rows then fall back to no icon for those classes).
for g in windows11 efi snapshots; do rsvg-convert -w 64 -h 64 -o "$STAGE/$g.png" "$STAGE/$g.svg"; done
for ic in cachyos linux; do
  src="/usr/share/grub/themes/cachyos/icons/$ic.png"
  if [ -f "$src" ]; then
    cp -f "$src" "$STAGE/$ic.png"
  else
    echo "build-assets: stock icon $src missing (install the CachyOS theme for full icons); skipping" >&2
  fi
done
for ic in cachyos linux windows11 efi snapshots; do
  [ -f "$STAGE/$ic.png" ] || continue
  magick "$STAGE/$ic.png" -trim +repage -resize 48x48 -background none -gravity center \
    -extent 64x64 -depth 8 PNG32:"$DIR/icons/$ic.png"
done

# ---------- fonts ----------
# Font roots differ per distro (Arch: /usr/share/fonts/TTF, Debian: /usr/share/fonts/{truetype,opentype}),
# filenames differ too (Cantarell ships as one variable font here, static Regular/Bold there), and a
# silent miss produces a theme with no fonts at all — so glob across the roots and, on failure, print
# what is actually installed instead of guessing again.
cantarell() { # $1 = filename glob
  for d in /usr/share/fonts/cantarell /usr/share/fonts/truetype/cantarell \
           /usr/share/fonts/opentype/cantarell /usr/share/fonts/OTF /usr/local/share/fonts; do
    for f in "$d"/$1; do
      [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }
    done
  done
  return 1
}
anywhere() { # $1 = filename glob, searched over every font root
  for f in /usr/share/fonts/*/$1 /usr/share/fonts/*/*/$1 /usr/local/share/fonts/$1; do
    [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }
  done
  return 1
}
VF=$(cantarell 'Cantarell-VF.[ot]tf') || VF=""
CANT_REG=$(cantarell 'Cantarell-Regular.[ot]tf') || CANT_REG=""
CANT_BOLD=$(cantarell 'Cantarell-Bold.[ot]tf') || CANT_BOLD=""
DEJAVU=$(anywhere 'DejaVuSans.ttf') || DEJAVU=""

report_missing() {
  echo "build-assets: $1 not found. Installed font files matching the project's needs:" >&2
  ls /usr/share/fonts/*/cantarell/ /usr/share/fonts/*/*/cantarell/ 2>/dev/null >&2 || echo "  (no cantarell directory)" >&2
  ls /usr/share/fonts/*/dejavu/ /usr/share/fonts/*/*/dejavu/ 2>/dev/null >&2 || echo "  (no dejavu directory)" >&2
}
[ -n "$DEJAVU" ] || { report_missing "DejaVuSans.ttf (install fonts-dejavu-core)"; exit 1; }

# No -n: grub-mkfont derives "<Family> <Style> <Size>" from the font itself, which is the
# name GRUB looks up. Passing -n sets the *family*, and every lookup then misses to Unifont.
if [ -n "$VF" ]; then
  grub-mkfont -s 48 -b -o "$DIR/cantarell_bold_48.pf2"    "$VF"
  grub-mkfont -s 24    -o "$DIR/cantarell_regular_24.pf2" "$VF"
  grub-mkfont -s 19    -o "$DIR/cantarell_regular_19.pf2" "$VF"
elif [ -n "$CANT_REG" ] && [ -n "$CANT_BOLD" ]; then
  grub-mkfont -s 48 -b -o "$DIR/cantarell_bold_48.pf2"    "$CANT_BOLD"
  grub-mkfont -s 24    -o "$DIR/cantarell_regular_24.pf2" "$CANT_REG"
  grub-mkfont -s 19    -o "$DIR/cantarell_regular_19.pf2" "$CANT_REG"
else
  report_missing "Cantarell (install fonts-cantarell)"
  exit 1
fi
# glyph fallback so @KEYMAP@ hints and any stray arrow never render as tofu
grub-mkfont -s 15    -o "$DIR/dejavu_sans_15.pf2"       "$DEJAVU"
# monospace face for the 'c' shell: copied from the stock CachyOS theme when this machine has one.
# Optional by design — without it the shell uses whichever font loaded (cosmetic, never fatal).
if [ -f /usr/share/grub/themes/cachyos/terminus-18.pf2 ]; then
  cp -f /usr/share/grub/themes/cachyos/terminus-18.pf2 "$DIR/terminus-18.pf2"
else
  echo "build-assets: no stock terminus-18.pf2; the 'c' shell will use a fallback font" >&2
fi

rm -rf "$STAGE"
echo "cachyos-pro assets rebuilt in $DIR"
