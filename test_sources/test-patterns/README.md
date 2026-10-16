# madeitpx test patterns (PNG, RGBA)

| File | Tests |
|---|---|
| 01_hue_gradient | smooth color gradient, palette quantization, dithering-like banding |
| 02_gray_ramps | smooth + 16/8/4-level grayscale; palette_colors 2..64 |
| 03_swatches_64_colors | 64 distinct colors; palette 64 should preserve, 16/32 should merge |
| 04_near_duplicate_colors | similar shades must merge into base colors |
| 05_alpha_ramps | alpha 0..255 composited on background_rgb; hidden RGB under alpha 0 |
| 06_alpha_soft_circle | soft alpha edge, transparent corners |
| 07_checkerboards_1_2_4_8px | area vs nearest sampling |
| 08_color_stripes_fine | color mixing under area sampling (fine RGB stripes) |
| 09_isolated_pixels_cleanup | cluster_cleanup: similar-color specks removed, 60 high-contrast dots kept |
| 10_noisy_gradient | noise robustness |
| 11_lines_shapes_text | thin lines, circles, text detail |
| 12_scene_sprite | pixel-art-like scene with flat colors |
| 13_plasma_photo_like | photo-like smooth multicolor |
| 14_extreme_colors | pure black/white/primaries |
| 15_odd_size_* | 1x1, 1x100, 100x1, 37x23, 1000x3, 7x513, 2x2, 255x257: bounds, stride, grid > source |
| 16_alpha_checker_over_plasma | semi-transparent over complex colors |

Run `python tests/render_patterns.py` after `zig build -Doptimize=ReleaseFast` to
generate preset and sampling previews in `test_sources/output/`. Compare the
results in [`results.md`](../output/results.md) or open
[`index.html`](../output/index.html).
