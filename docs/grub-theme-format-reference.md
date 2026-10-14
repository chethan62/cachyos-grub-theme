# GNU GRUB 2 graphical theme file format — property-level reference (2.12 – 2.16)

## Sources (all primary)

| Ref | What | URL |
|---|---|---|
| **MAN** | GRUB manual, node *Theme file format* (currently 2.14) | https://www.gnu.org/software/grub/manual/grub/html_node/Theme-file-format.html |
| **TEXI** | `docs/grub.texi` theme chapter (upstream text) | https://git.savannah.gnu.org/cgit/grub.git/tree/docs/grub.texi (mirror used: https://raw.githubusercontent.com/coreos/grub/master/docs/grub.texi) |
| **TL** | `grub-core/gfxmenu/theme_loader.c` — the actual parser | https://sources.debian.org/src/grub2/2.16-1/grub-core/gfxmenu/theme_loader.c/ (canonical: https://git.savannah.gnu.org/cgit/grub.git/tree/grub-core/gfxmenu/theme_loader.c) |
| **LBL / PB / CP / LS / IMG / BOX / CANV** | `gui_label.c`, `gui_progress_bar.c`, `gui_circular_progress.c`, `gui_list.c`, `gui_image.c`, `gui_box.c`, `gui_canvas.c` | https://sources.debian.org/src/grub2/2.16-1/grub-core/gfxmenu/ |
| **WBOX** | `widget-box.c` — styled-box 9-slice engine | https://sources.debian.org/src/grub2/2.16-1/grub-core/gfxmenu/widget-box.c/ |
| **VIEW** | `view.c` — root view, desktop image, terminal | https://sources.debian.org/src/grub2/2.16-1/grub-core/gfxmenu/view.c/ |
| **ICON** | `icon_manager.c` — menu entry icons | https://sources.debian.org/src/grub2/2.16-1/grub-core/gfxmenu/icon_manager.c/ |
| **COL** | `grub-core/video/colors.c` — `grub_video_parse_color` | https://sources.debian.org/src/grub2/2.16-1/grub-core/video/colors.c/ |
| **FONT** | `grub-core/font/font.c` — `grub_font_get` | https://sources.debian.org/src/grub2/2.16-1/grub-core/font/font.c/ |
| **PNG** | `grub-core/video/readers/png.c` | https://sources.debian.org/src/grub2/2.16-1/grub-core/video/readers/png.c/ |
| **BMP / BSC** | `video/bitmap.c`, `video/bitmap_scale.c` | https://sources.debian.org/src/grub2/2.16-1/grub-core/video/ |
| **MISC** | `kern/misc.c` — `grub_printf_fmt_check` | https://sources.debian.org/src/grub2/2.16-1/grub-core/kern/misc.c/ |
| **ARCH** | Arch Wiki GRUB page (no theme-format detail; only `GRUB_THEME`, module list) | https://wiki.archlinux.org/title/GRUB |

Version checked: **2.16-1** in full, cross-checked line-by-line against **2.14-4** and **2.12-9+deb13u2** for every claim marked *(version)* below. The theme format itself is byte-stable across 2.12→2.16; only hardening differs.

Exact property names, defaults and semantics below are read from the source, not the manual. Where the manual disagrees with the code, the code is quoted.

---

## 1. File grammar (TL, `read_property` / `read_object` / `read_expression`)

* Plain UTF-8 text. `#` at a **statement boundary** starts a comment to end-of-line. Inside a component body, comments are also honoured between property assignments.
* Two statement kinds: **global property** (`name: value`) and **component** (`+ type { ... }`).
* **Global values must be double-quoted.** `read_property` does `if (peek_char(p) == '"') read_expression(...); else error("property value invalid; enclose literal values in quotes")`. The manual's `name1: value1` / `name3: #88F` examples are **not accepted** by 2.12–2.16 — write `name3: "#88F"`. *(version: true in 2.12, 2.14, 2.16)*
* Component values: bare word (no whitespace), `"quoted string"`, or `( ... )` up to the first `)`. Whitespace around tokens is ignored.
* Property/type names: `[A-Za-z0-9_-]+` — hyphens and underscores both legal, case-sensitive.
* Component types recognised (exact, `TL::read_object`): `label`, `image`, `vbox`, `hbox`, `canvas`, `progress_bar`, `circular_progress`, `boot_menu`. Anything else → `unknown object type 'x'`.
* Containers only: `canvas`, `hbox`, `vbox` (`is_instance(component,"container")`). A `+` inside a non-container → `attempted to add object to non-container`.
* The root is an implicit `canvas` sized to the framebuffer (`VIEW::grub_gfxmenu_view_new`); top-level `+` components are its children. It has no id and cannot be addressed.
* **Asymmetry that bites:** an **unknown global** property is a hard error (`unknown property 'x'`) that aborts the whole theme. An **unknown component** property is **silently ignored** (every `*_set_property` falls through its if/else chain and returns no error). Typos on component properties cost you nothing but silently do nothing.

---

## 2. Global properties (`[name: "value"]`, TL::theme_set_string)

| Property | Type | Default | Semantics |
|---|---|---|---|
| `title-text` | string | `"GRUB Boot Menu"` (translated) | Drawn **top-centre**, `y = 40 + ascent` (`VIEW::draw_title`). Cannot be left/right-aligned — use a `+ label` for that. Empty string = blank. |
| `title-font` | string | first loaded font | Font for the title string. |
| `title-color` | color | `#000000` | Title colour. |
| `message-font` | string | first loaded font | **Inert.** The only drawing path (`VIEW::draw_message`) is inside `#if 0`. Manual: "currently unused". |
| `message-color` | color | `#FFFFFF` | Inert (same). |
| `message-bg-color` | color | `#000000` | Inert (same). |
| `desktop-image` | string | none | Background image, resolved relative to the theme dir. Loaded immediately. **Load failure is fatal** (aborts theme). |
| `desktop-image-scale-method` | enum | `stretch` | `stretch` \| `crop` \| `padding` \| `fitwidth` \| `fitheight`. Empty string = `stretch`. Anything else → `Unsupported scale method`. |
| `desktop-image-h-align` | enum | `center` | `left` \| `center` \| `right`. Only used when method ≠ `stretch`. Unknown → `Unsupported horizontal align method`. |
| `desktop-image-v-align` | enum | `center` | `top` \| `center` \| `bottom`. Only when method ≠ `stretch`. Unknown → `Unsupported vertical align method`. |
| `desktop-color` | color | `#FFFFFF` | Fill when no desktop image, and the base under letterbox/pad areas. |
| `terminal-box` | string | empty box | Styled-box **pattern** for the gfxterm frame, e.g. `terminal_*.png`. |
| `terminal-border` | int | `3` | gfxterm internal border width. |
| `terminal-left` | proportional | centred | gfxterm rect x. |
| `terminal-top` | proportional | centred | gfxterm rect y. |
| `terminal-width` | proportional | 70 % of screen | gfxterm rect width. |
| `terminal-height` | proportional | 70 % of screen | gfxterm rect height. |
| `terminal-font` | string | `"Fixed 10"` | **Implemented, undocumented** (TL line ~182). Cannot be changed at runtime once gfxterm is up (`VIEW::init_terminal`). |

The documented global list is exactly the table above minus `terminal-font` (TEXI lines 164–216).

---

## 3. Common / positional properties (TL::read_object — intercepted *before* the component sees them)

| Property | Type | Default | Semantics |
|---|---|---|---|
| `left` | proportional | `0` | x offset inside the parent container. |
| `top` | proportional | `0` | y offset inside the parent container. |
| `width` | proportional | `0` | width (canvas: also used to clip). |
| `height` | proportional | `0` | height. |
| `id` | string | none | Free-form. Exactly one value is special: `"__timeout__"` (`GRUB_GFXMENU_TIMEOUT_COMPONENT_ID`), honoured only by `label`, `progress_bar`, `circular_progress`. |

**Proportional spec grammar** (`TL::parse_proportional_spec`): a *sum of terms*; each term is `[+-]N` (pixels) or `[+-]N%` (fraction of the container dimension). So `50%+8`, `-4`, `25%-2+3%` all parse.

* Final value = `container_size * (sum of % terms) + (sum of px terms)`.
* Canvas children: `x = xfrac*w + x`, `w = wfrac*w + w` (`CANV::canvas_paint`).
* **2.16 only:** any single term > 30000 → `proportional value out of range` (overflow hardening, `PROPORTIONAL_TERM_MAX`). Not present in 2.12/2.14. *(version)*
* A bad spec sets `grub_errno`, and `read_object` propagates it → theme aborts.

`left`/`top` are **ignored by `hbox`/`vbox`** (they assign x/y themselves) and on canvas children are interpreted inside the canvas, not the screen.

---

## 4. Components and their properties

Rendering-order note: positional properties are resolved by the parent at **paint time**, and box pixmaps are (re)created lazily at first paint.

### 4.1 `label` (LBL)

| Property | Type | Default | Semantics |
|---|---|---|---|
| `id` | string | – | `"__timeout__"` → text is regenerated each tick from the template. |
| `text` | string | `""` | Supports `@KEYMAP_LONG@` / `@KEYMAP_MIDDLE@` / `@KEYMAP_SHORT@` substitution and one `%d`. See §5a. |
| `font` | string | first loaded font | – |
| `color` | color | `#000000` (α=255) | – |
| `align` | enum | `left` | `left` \| `center` \| `right`, within the component's own `width`. Unknown value is silently ignored. |
| `visible` | bool | `true` | Anything other than the literal `false` = visible. |

No `@TIMEOUT_NOTIFICATION_*` support here (contrast `progress_bar`).

### 4.2 `image` (IMG)

| Property | Type | Default | Semantics |
|---|---|---|---|
| `file` | string | – | Path **relative to the theme dir** (or absolute / `(hd0,0)/...`). Scaled to the component bounds with `GRUB_VIDEO_BITMAP_SCALE_METHOD_BEST`. |
| `id` | string | – | Not special. |

No `visible`. A failed load **propagates an error → whole theme aborts**.

### 4.3 `progress_bar` (PB)

| Property | Type | Default | Semantics |
|---|---|---|---|
| `id` | string | – | `"__timeout__"` → driven by the countdown; hidden when interrupted. |
| `text` | string | none | printf template with one `%d` (seconds), or `@TIMEOUT_NOTIFICATION_SHORT/MIDDLE/LONG@`. See §5b. |
| `font` | string | first loaded font | Text font. |
| `text_color` | color | `#000000` | Text. |
| `border_color` | color | `#000000` | 1-px outline, solid-fill mode only. |
| `bg_color` | color | `#808080` | Empty part, solid-fill mode. |
| `fg_color` | color | `#C8C8C8` | Elapsed part, solid-fill mode. |
| `bar_style` | string | none | Styled-box pattern for the frame, e.g. `progress_frame_*.png`. |
| `highlight_style` | string | none | Styled-box pattern for the elapsed region, e.g. `progress_hl_*.png`. |
| `highlight_overlay` | bool | `false` | `true` → highlight side slices overlay the frame's, and the highlight centre can span the full height. |

### 4.4 `circular_progress` (CP) — *not* `circular_progress_image`

| Property | Type | Default | Semantics |
|---|---|---|---|
| `id` | string | – | `"__timeout__"` supported. |
| `center_bitmap` | string | none | Image drawn centred. |
| `tick_bitmap` | string | none | Image stamped `num_ticks` times round a circle. |
| `num_ticks` | int | `64` | Ticks per full circle. `0` disables tick drawing. |
| `start_angle` | angle | `-64` | In 1/256-turn units ("parrots"); `N deg` or `N°` converted as `round(N*64/90)`. `-64` = 90° anticlockwise = top. |
| `ticks_disappear` | bool | `false` | `true` → ticks vanish as time runs out; default → they appear. |

No `text`/`font`/`visible` property. Both bitmaps must load or **nothing at all** is drawn (silently).

### 4.5 `boot_menu` (LS)

| Property | Type | Default | Semantics |
|---|---|---|---|
| `id` | string | – | Not special. |
| `item_font` | string | first loaded font | Item titles. |
| `selected_item_font` | string / `inherit` | `inherit` | `inherit` (= omitted) tracks `item_font`. |
| `item_color` | color | `#000000` | – |
| `selected_item_color` | color / `inherit` | `inherit` | Tracks `item_color` unless set. |
| `icon_width` / `icon_height` | int | `32` / `32` | Icons scaled to this. |
| `item_height` | int | `42` | Row height in px. |
| `item_padding` | int | `14` | Inset on every side of the menu contents. |
| `item_icon_space` | int | `4` | Gap icon→text. |
| `item_spacing` | int | `16` | Gap between rows. |
| `menu_pixmap_style` | string | none | Styled box for the whole menu frame. |
| `item_pixmap_style` | string | none | Styled box per (unselected) row. |
| `selected_item_pixmap_style` | string / `inherit` | `inherit` | Tracks `item_pixmap_style`. |
| `scrollbar` | bool | `true` | Master switch; drawn only if it also fits. |
| `scrollbar_frame` | string | none | Pattern for the track. |
| `scrollbar_thumb` | string | none | Pattern for the thumb. |
| `scrollbar_thumb_overlay` | bool | `false` | As `highlight_overlay` but for the thumb. |
| `scrollbar_slice` | enum | `east` | `west` \| `center` \| `east`. See §5e. |
| `scrollbar_width` | int | `16` | **Undocumented**, real. |
| `scrollbar_left_pad` | int | `2` | */ |
| `scrollbar_right_pad` | int | `0` | */ |
| `scrollbar_top_pad` | int | `0` | */ |
| `scrollbar_bottom_pad` | int | `0` | */ |
| `visible` | bool | `true` | – |

Icons: looked up by menu-entry **class name** as `<theme-dir>/icons/<class>.png`, then `$icondir/<class>.png` (`ICON::get_icon_by_class`); extension hard-coded `.png`; first class that resolves wins; none → no icon, silently.

### 4.6 Containers `canvas`, `hbox`, `vbox`

Only property: **`id`** (plus the four positional ones). **No `visible`** — setting `visible = false` on a container is silently ignored.

* `canvas` (CANV): children keep their own `left/top/width/height` (+ percentages). Before painting, a child's size is raised to its **minimal size** and then clamped: `w<=0 → 32`, `h<=0 → 32`, `x<0 → 0`, `x ≥ width → width-32`, and `x+w > width → w = width-x` (hard clip at the right/bottom edge). No layering: later children are pushed to the front of the list but there is no z-order guarantee (source has `TODO Add layering`).
* `hbox` (BOX): lays children left→right. Width = `width` spec (px + %×box width), raised to minimal width; height = box height. Children's `top` is ignored.
* `vbox`: mirror image (top→bottom, height from the spec, width = box width).

---

## 5. The details that are undocumented or surprising

### (a) Label text markup — and the `^x` question

There is **no** hotkey/mnemonic markup and **no** escape sequences in `label.text` — the string is passed straight to `grub_font_draw_string`. In particular **`^` is not special**: `grub-core/normal/menu_text.c` and `gui_list.c` both draw the menu-entry title verbatim (no caret, no underline). The `^x` hotkey syntax is a *GRUB Legacy / gfxmenu-0.9x* convention; it does not exist in GRUB 2. (Searched all of theme_loader.c, gui_*.c, widget-box.c, view.c, icon_manager.c, menu_text.c for `^`, `hotkey`, `mnemonic` — zero matches.)

What **is** supported (LBL::label_set_property) is three hard-coded, translatable substitutions, applied **when the property is parsed**:

| Token | Expansion (English msgid) |
|---|---|
| `@KEYMAP_LONG@` | `Press enter to boot the selected OS, \`e' to edit the commands before booting or \`c' for a command-line. ESC to return previous menu.` |
| `@KEYMAP_MIDDLE@` | `Press enter to boot the selected OS, \`e' to edit the commands before booting or \`c' for a command-line.` |
| `@KEYMAP_SHORT@` | `enter: boot, \`e': options, \`c': cmd-line` |

After substitution the result is validated with `grub_printf_fmt_check(value, "%d")`; **if the string is not a valid single-`%d` format it is replaced with `""` — the label goes silently blank.** Consequences (`MISC::parse_printf_arg_fmt`):

* A literal percent must be written `%%`. A lone `%` (e.g. `text = "100%"`) is `unexpected format`.
* Positional args (`%1$d`) and any conversion other than `d i u o x X c C s p` are rejected.
* The rejected call **leaves `grub_errno` set**, which `TL::read_object` then propagates → the theme load aborts with `unexpected format`. *(inferred from source, not boot-tested)*

`@TIMEOUT_NOTIFICATION_*` is **not** a label token. It exists only in `progress_bar.text` (PB::progress_bar_set_property). If you write it in a label you get the literal text `@TIMEOUT_NOTIFICATION_MIDDLE@`.

For a label, the timeout text is produced by a raw template instead: with `id = "__timeout__"`, `label_set_state` does `text = xasprintf(template ?: "%d", seconds)`, so `text = "Booting in %ds"` works and prints positive seconds. (The value handed to the label is `-current` where current is `-timeout`, so it's positive.)

### (b) `progress_bar` with `id = "__timeout__"`

* With that id, `grub_gfxmenu_timeout_register` binds the component; `VIEW::update_timeouts(1, -first_timeout, -timeout, 0)` drives it, and `grub_gfxmenu_clear_timeout` calls `update_timeouts(0, 1, 0, 0)` — i.e. **`visible` is forced to 0 the moment the countdown is cancelled** by a keystroke ("press any key"). Don't design a bar you want to keep on screen during a manual selection.
* `text` handling (PB::~line 376): the three `@TIMEOUT_NOTIFICATION_*` tokens expand to `"%ds"`, `"%ds remaining."`, `"The highlighted entry will be executed automatically in %ds."` respectively; then the same `%d` format check as labels applies and a bad template silently blanks the text.
* The `%d` argument is `abs(value)`, so `" in %ds"` prints a positive number.

**Solid-colour bar is fully legitimate — it is the default.** Source (`PB::progress_bar_paint` → `check_pixmaps` → `draw_pixmap_bar` / `draw_filled_rect_bar`):

* `pixmapbar_available` is only set when `bar_style` **or** `highlight_style` is assigned. If neither is, `check_pixmaps()` returns 0 and GRUB renders three `grub_video_fill_rect` calls: a 1-px `border_color` ring around the whole bounds, `fg_color` for the elapsed fraction, `bg_color` for the remainder. Width = `(bounds.width-2) * (value-start)/(end-start)`.
* **Trap:** assigning *only one* of `bar_style`/`highlight_style` flips the component into pixmap mode. The unset one becomes `grub_gfxmenu_create_box(0,0)` — a valid, empty box — so `check_pixmaps()` still returns 1 and the solid fill is **suppressed entirely**. Set both, or neither.
* `highlight_overlay = true` makes the highlight's side slices sit *over* the frame's (`tracklen += hl_h_pad; hlx -= hl_l_pad; hly -= hl_t_pad`) so a rounded highlight can travel the full height with no gap at the ends. Default `false`.
* **Manual discrepancy:** MAN/TEXI both say *"If the value is equal to `highlight_style` then no styled boxes will be shown"* (and vice versa). Grepping `gui_progress_bar.c` in 2.12, 2.14 and 2.16 shows **no such comparison exists** — `bar_pattern` and `highlight_pattern` are stored independently and both boxes are always created. Treat that manual sentence as stale.

### (c) `circular_progress` with `id = "__timeout__"`

Fully supported and registered the same way (`CP::circprog_set_property`). The value handed in is again `-timeout`, and the tick count is `num_ticks * (value-start)/(end-start)` with `start=-first_timeout, end=0`, so the ring **fills up** as the countdown runs (or empties if `ticks_disappear`). Same auto-hide on interruption. The component is named `circular_progress`; there is **no** `circular_progress_image` type. It has no `visible` property and no text.

### (d) Containers, `id`, "preferred_size", `visible`

* Containers accept **only `id`** (CSS-style) — plus the four positional properties. There is no `visible`, no padding/margin/spacing property.
* There is **no `preferred_size` property anywhere.** The manual's `preferred_size = (120, 80)` is only an illustration of the *tuple value syntax*; no component reads it, and because unknown component properties are ignored it is a harmless no-op.
* "Preferred size" is instead the **minimal size** each component computes (`get_minimal_size`) and the parent then enforces: `label` = text width × (ascent+descent); `image` = raw pixel size; `progress_bar` = text + pixmap pads, floor 200×28; `boot_menu` = `item_height*3 + spacing*2 + 2*item_padding + menu/item pads`, width from `"Typical OS"`; `hbox`/`vbox` = derives from children.
* `visible = false` is honoured by `label`, `progress_bar` (and by `boot_menu`). It is **silently ignored** on `canvas`, `hbox`, `vbox`, `image`, `circular_progress`. To hide a group, put it in a `vbox`/`canvas` and give the whole thing zero size, or use `image`+no file… better: wrap the members whose `visible` does work.

### (e) `boot_menu` scrollbar properties and `scrollbar_slice`

Drawn only if `scrollbar` ≠ `false` **and** `num_shown_items < menu size` **and** `check_scrollbar()` passes (frame pads ≤ `scrollbar_width`, and total required height ≤ menu height; otherwise `draw_scrollbar` is cleared and the bar silently never appears).

`scrollbar_slice` controls where the track is carved out of the menu box (LS::list_paint):

* `east` (default) — drawn in the menu frame's **east** slice (`x = bounds.width - box_right_pad`, width = `box_right_pad`, left-aligned in it). With no `menu_pixmap_style` the east pad is 0 → the track gets a 0-px viewport → effectively invisible. **This is why the default scrollbar "doesn't show".**
* `west` — drawn right-aligned in the **west** slice; `scrollbar_right_pad` reserved out of the content.
* `center` — drawn inside the **centre** slice at the right; when drawn, the item viewport width is reduced by `scrollbar_width + left_pad + right_pad`. Works with **no** `menu_pixmap_style` at all.

`scrollbar_left_pad` is meaningless with `west`, `scrollbar_right_pad` with `east`. `scrollbar_thumb_overlay` (=`scrollbar_thumb_overlay`) behaves like `highlight_overlay`. Geometry uses `value=first_shown_index, extent=num_shown_items, min=0, max=menu size`.

### (f) `desktop-image-scale-method` and h/v-align

`VIEW::init_background` → `stretch` uses `grub_video_bitmap_create_scaled(screen.w, screen.h, …)`; every other value uses `grub_video_bitmap_scale_proportional(...)` (`BSC`, lines 265–296). With `sw,sh` = source size, `dw,dh` = screen:

| Method | When `sw·dh < dw·sh` (image relatively wider) | Otherwise |
|---|---|---|
| `crop` | crop source vertically, scale to full width | crop source horizontally, scale to full height |
| `padding` | letterbox: pad the **destination width** using `h-align` | pillar-box the destination height using `v-align` |
| `fitwidth` | crop source vertically (align `v`) | pad destination height (align `v`) |
| `fitheight` | pad destination width (align `h`) | crop source horizontally (align `h`) |
| `stretch` | scale both axes to the screen (distorts) | — |

`h-align` only bites in the branches that touch `dx0/dw`; `v-align` only in `dy0/dh`. `desktop-color` shows through the padding in `padding`/`fit*` modes.

### (g) Styled boxes: 9-slice rules and the suffix set (WBOX)

Pattern form is `prefix*Suffix` — e.g. `menu_*.png` → prefix `menu_`, suffix `.png`. The `*` is mandatory: **no `*` → error `missing '*' in box pixmap pattern`** (and an empty pattern `""` therefore errors too).

Substitution order and exact suffix strings (`box_pixmap_names[]`), 9 files:

```
corners: nw  ne  se  sw
sides:   n   e   s   w
centre:  c
```

Scaling (`WBOX::set_content_size`, called with the content box in px):

1. `n` and `s` are scaled to the content **width** (height preserved).
2. `e` and `w` are scaled to the content **height** (width preserved).
3. `nw`, `ne`, `sw`, `se` are **never scaled**.
4. `c` is scaled to width × height.

Drawing (`WBOX::draw`): side/edge height is `max(height(nw), height(n), height(ne))`; side/edge width is `max(width(nw), width(w), width(sw))`; corners then centre.

Pads the box reports to callers — these are what shifts labels/items:

* `left_pad  = max(w(W), w(NW), w(SW))`
* `top_pad   = max(h(N), h(NW), h(NE))`
* `right_pad = max(w(E), w(NE), w(SE))`
* `bottom_pad= max(h(S), h(SW), h(SE))`

An empty box (`create_box(0,0)`) has all pads 0 and draws transparent. If you supply only some slices, the missing ones contribute 0 to the pads, so a missing corner silently changes your text offsets.

### (h) Failure modes when a font / slice / image is missing

| Missing thing | Code path | Behaviour |
|---|---|---|
| **Styled-box slice** (menu/item/selected/highlight/scrollbar/terminal) | `WBOX::grub_gfxmenu_create_box`: `grub_video_bitmap_load(...)` return is **discarded**, then `grub_errno = GRUB_ERR_NONE` (explicit `/* Ignore missing pixmaps. */`) | **Silent.** That slice draws nothing; the box still exists; pads shrink to 0 for it. No message anywhere. |
| **Unreadable/invalid PNG** for a slice | same | **Silent**, identical to missing. |
| **`image` component `file`** | `IMG::load_image` returns the load error → `image_set_property` returns it | **Fatal**: `unknown`/file error propagates out of `read_object`; `grub_gfxmenu_view_load_theme` fails, the view is destroyed, GRUB falls back to the text menu. |
| **`desktop-image`** | `TL::theme_set_string` returns `grub_errno` on load failure | **Fatal**, same as above. |
| **Menu-entry icon** | `ICON::try_loading_icon` discards the result and does `grub_errno = GRUB_ERR_NONE` | **Silent**, falls through the class list; no icon. |
| **`circular_progress` bitmaps** | `CP::load_bitmap` discards the error and clears `grub_errno`; `check_pixmaps` false → `circprog_paint` returns | **Silent**, nothing drawn. |
| **Font name not found** | `FONT::grub_font_get` — after scanning for an exact match it **returns the first font in the loaded list**; only if none are loaded does it return `null_font` (name `<No Font>`) | **Silent and misleading**: a typo'd `item_font`/`title-font` renders in whatever font happened to load first (usually Unifont), never an error. This is why a "missing font" looks like "wrong font", not "no text". (The gfxterm `terminal-font` is the one place that errors: `VIEW::init_terminal` → `no font loaded`.) |

---

## 6. Colours (COL::grub_video_parse_color) — refines the manual

Accepted forms:

* `#RGB`, `#RGBA`, `#RRGGBB`, **`#RRGGBBAA`** — hex digits counted, then components expanded.
* decimal `r,g,b` **or `r,g,b,a`**, parsed with `grub_strtoul(..., base 0)` (so `0x`, decimal, even octal).
* lowercase SVG 1.0 colour names via `grub_video_get_named_color`.

Anything else → `invalid color specification '...'` and (because callers ignore the return while leaving `grub_errno` set) the theme load aborts.

The manual only documents `#RGB`/`#RRGGBB`/decimal-RGB/names. **Alpha is supported in 2.12 through 2.16** (`#RGBA`/`#RRGGBBAA` present in all three; verified). Whether it visually blends for a given primitive is a property of the render path, not the parser.

---

## 7. Things most themes get wrong

1. **Unquoted global values.** `title-color: #fff` is a parse error; it must be `title-color: "#fff"`.
2. **Literary `%` in text.** `text = "100% complete"` → `unexpected format`; write `%%`. The same applies to a `progress_bar` `text` template.
3. **Setting only one of `bar_style` / `highlight_style`** on a progress bar silently disables the solid-colour rendering (turns on pixmap mode with one empty box).
4. **Typo'd component property = silent no-op**; typo'd global property = theme refuses to load. Check component names by hand; there is no warning.
5. **Missing styled-box slices are silent.** An invisible selection highlight is usually a missing/renamed `<prefix>c.png` or `nw.png`, or a slice whose pads ended up 0 — not a layout bug.
6. **A missing `image`/`desktop-image` is fatal**, the opposite of a missing slice. One bad background path drops you into the text menu with no theme.
7. **Font names fail open.** A wrong font is not an error; it falls back to the first loaded font. Verify with `lsfonts` at the GRUB prompt.
8. **The default `scrollbar_slice = east` needs `menu_pixmap_style`.** Without a menu pixmap the east pad is 0 and the scrollbar has nowhere to draw; use `scrollbar_slice = "center"` instead.
9. **`boot_menu` `height` must be ≥ `items × item_height + (items-1) × item_spacing` + box/item pads**, else the last entries are clipped — looks like missing entries, not a sizing issue.
10. **`visible = false` on a container does nothing.** Hoist `visible` onto the leaf components.
11. **`selected_item_font` set to a genuine bold face reflows rows** — the ascent/descent change shifts text when the selection moves. Use `inherit` and let the highlight box carry the selection.
12. **`highlight_overlay` / `scrollbar_thumb_overlay` default to `false`**; a rounded highlight that leaves a gap at the extremes needs `true`.
13. **`^x` does not exist.** Neither do `\n` escapes, hotkeys, or underline markup in labels or menu entries.
14. **`@TIMEOUT_NOTIFICATION_*` is progress-bar-only**, and the `__timeout__` bar/label vanish the instant the user presses a key.
15. **Undocumented-but-real:** `terminal-font`, `scrollbar_width`. **Documented-but-inert:** `message-font`, `message-color`, `message-bg-color`. **Documented-but-not-implemented:** the `bar_style == highlight_style` "no styled boxes" rule; `preferred_size`.
16. **Colours can carry alpha** (`#RRGGBBAA`, `r,g,b,a`) since 2.12, despite the manual.

---

## 8. Could not confirm / corrections to prior belief

* **PNG palette rejection — the premise is wrong for 2.12–2.16.** `PNG::grub_png_decode_image_header` explicitly accepts `PNG_COLOR_TYPE_PALETTE` (`is_palette = 1`), supports bit depths 1/2/4 (4-bit only for palette) and 8, and decodes via `grub_png_decode_image_palette` / the `PLTE` chunk handler. Present identically in 2.12, 2.14, 2.16 (all three `png.c` blobs carry `is_palette`). What the module actually **rejects**: grayscale (colour type 0) and grayscale+alpha (4) → `png: color type not supported`; 16-bit palette; interlaced PNGs → `png: interlace method not supported`. What it **ignores**: `tRNS` — the chunk switch handles only `IHDR`, `PLTE`, `IDAT`, `IEND`; everything else is skipped, so palette/greyscale transparency is lost and such slices render fully opaque. So if a monochrome-ish export "silently doesn't draw the right thing", the likely culprit is a **grayscale** PNG (or lost tRNS), not a palette PNG. (I could not reproduce the reported failure — this is a source-level finding.)
* **Colour alpha:** the manual says RGB only; the code accepts `#RGBA`/`#RRGGBBAA`/4-component decimal in 2.12–2.16. Whether alpha actually blends through `grub_video_map_rgba_color` for every primitive was not tested.
* **Manual sentence** *"If the value is equal to `highlight_style` then no styled boxes will be shown"* (and its mirror for `highlight_style` vs `bar_style`) — present in the 2.14 manual/TEXI but **not implemented** in 2.12/2.14/2.16 `gui_progress_bar.c` (no equality test exists). I read the shipped release tarball, not git master; master may differ.
* **`grub-mkfont -n` behaviour** — not investigated (out of scope per your note).
* **Manual version:** the HTML node on gnu.org is 2.14, i.e. one release behind your 2.16. `docs/grub.texi` was read from a mirror that may not be the exact 2.16 tag; every claim above that matters was therefore verified against the **2.16-1 release source**, not the manual.
* **2.15** was not checked separately (no Debian package); 2.12 and 2.14 bracket it and agree with 2.16 on every item here except the `PROPORTIONAL_TERM_MAX` bound.
