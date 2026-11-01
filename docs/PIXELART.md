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
- `docs/pixelart_prototype/` is a Python reference for stages 1, 2 and 4. Its palette step is its own median-cut, so palettes can differ from the Zig build (which reuses `palette.zig`).

## Version 2 (grid recovery)

`madeitpx_convert_pixelart_rgba8` takes a `madeitpx_pixelart_options` next to the usual options.
`madeitpx_convert_rgba8` with preset 3 is unchanged and still runs version 1, so existing callers
see no difference. Setting `version = 1` in the detailed options runs the same version 1 code.

Version 2 is for pixel art that was scaled up (non-integer factors, blur, JPEG noise) and should be
brought back to its real pixel grid. It shares no code with version 1. Give it the real grid size
as the target size (an 80x80 drawing upscaled to 256x256 uses target 80x80).

| Stage | What it does |
|---|---|
| Grid fit | Searches cell size (within `grid_search_permille` of source/target) and offset so cell borders land on image edges. |
| Sampling | Per-channel median of each cell after ignoring `sample_inset_percent` of every cell edge. |
| Palette | Cell colours within `color_tolerance` share a colour, merged down to `palette_max`, refined by `refine_iterations` k-means passes. |
| Output | One flat colour per cell. Single-cell details are kept. |

| Field | Default | Range |
|---|---|---|
| `version` | 2 | 1 or 2 |
| `grid_fit` | 1 | 0 or 1 |
| `grid_search_permille` | 30 | 0-200 |
| `sample_inset_percent` | 25 | 0-45 |
| `color_tolerance` | 14 | 0-442 |
| `palette_max` | 0 (automatic) | 0 or 2-256 |
| `refine_iterations` | 5 | 0-32 |

`madeitpx_pixelart_options_init` restores every field to its default, and
`madeitpx_pixelart_options_reset_field` restores a single field.
