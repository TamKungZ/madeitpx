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
