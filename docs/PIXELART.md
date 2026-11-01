# `pixelart` preset

Select with `options.preset = 3` (`Preset.pixelart`). Struct layout and ABI version are unchanged.
`sample_mode` is ignored (the preset does its own reduction). `palette_colors == 0` means 16.
`cluster_cleanup == 0` disables stage 4 only.

| Goal | Where it happens |
|---|---|
| Keep outlines / dark colours | Stage 1 keeps the *dark class* of an edge cell as ink when it covers >= 20% of the cell, instead of blending it into a grey. Stage 3 reserves 1-2 palette slots for ink colours, so they are never merged into mid-tones. Ink cells are never changed by stage 4. |
| Lines never break | Stage 2: thinning only removes a cell if 8-connectivity is preserved and never shortens a line end. From each line end, a gap is bridged if the line continues roughly straight: up to 2 missing cells without evidence, up to 5 if every missing cell has weak dark evidence in the source. Ends already connected within 12 cells are left alone (no loops forced, no parallel lines fused). |
| No isolated pixels | Stage 4: any non-ink cell not inside a 2x2 block of one colour is moved to the neighbouring solid colour closest to the cell's own source colour. Isolated ink specks are dropped in stage 2. |
| No 1px gradients | Same rule: a 1px band or 1px tooth can never be part of a 2x2 block, so every remaining shading band is >= 2 cells thick and every non-ink cluster has >= 4 cells. |

## Limits (by design, not bugs)
- Intentional single-pixel details (a 1px highlight in an eye, a lone sparkle) are removed. That is the requested behaviour.
- Lines thinner than ~12% of a cell, or with a gap > 2 cells and no source evidence, are not recovered.
- Dense hair-like strokes closer together than the output grid cannot stay separate; they become a hatch pattern.

## Version 2

`madeitpx_convert_pixelart_rgba8` takes a `madeitpx_pixelart_options` next to the usual options.
`madeitpx_convert_rgba8` with preset 3 is unchanged and still runs version 1, so existing callers
see no difference. Setting `version = 1` in the detailed options runs the same version 1 code.
Version 2 shares no code with version 1. Its source lives in `src/pixelart/v2/`.

`mode` picks what the source is. With `auto` (default) the grid search result decides: pixel art that
was scaled up has strong edges exactly on its cell borders, smooth artwork does not.

| Mode | Source | What happens |
|---|---|---|
| `grid` | Pixel art that was scaled up (non-integer factors, blur, JPEG noise) | The cell grid is recovered, each cell takes the median colour of its inner part, colours are merged into the real palette. Single-cell details are kept. Give the real grid size as the target size (an 80x80 drawing at 256x256 uses 80x80). |
| `illustration` | Smooth or detailed artwork | Each cell is reduced by area. Dark outlines are detected per cell, thinned to one cell across and given their own palette colours. The rest uses at most 32 colours (or `palette_max`), then cells in a minority and regions smaller than `min_region` are merged into their neighbours, so shading never breaks into dots. |

| Field | Default | Range | Used by |
|---|---|---|---|
| `version` | 2 | 1 or 2 | both |
| `mode` | 0 (auto) | 0 auto, 1 grid, 2 illustration | both |
| `grid_fit` | 1 | 0 or 1 | grid |
| `grid_search_permille` | 30 | 0-200 | grid |
| `sample_inset_percent` | 25 | 0-45 | grid |
| `color_tolerance` | 14 | 0-442 | both |
| `palette_max` | 0 (grid: automatic, illustration: 32) | 0 or 2-256 | both |
| `refine_iterations` | 5 | 0-32 | both |
| `ink_percent` | 20 | 0-100 (0 = no outlines) | illustration |
| `min_region` | 4 | 1-64 (1 = off) | illustration |
| `alpha_threshold` | 128 | 0-255 (0 = blend onto the background colour) | both |

Pixels with alpha below `alpha_threshold` are ignored instead of being blended into the background, so
faint fringes along a PNG's edge neither darken nor distort the outline. A cell is background when
fewer than half of its pixels are solid, and it is written as the background colour.

`madeitpx_pixelart_options_init` restores every field to its default, and
`madeitpx_pixelart_options_reset_field` restores a single field.

For artwork use a target size around a quarter of the source (1024x1536 to 256x384). Raise
`palette_max` for more tones, lower `min_region` to keep finer shading, set `ink_percent` to 0 to
drop outlines.
