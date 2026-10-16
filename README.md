<p align="center">
  <img
    src="assets/logo-wordmark.png#gh-light-mode-only"
    alt="Logo"
    width="320"
  />
  <img
    src="assets/logo-wordmark-dark.png#gh-dark-mode-only"
    alt="Logo"
    width="320"
  />
</p>

# madeitpx

`madeitpx` is a native image-processing library written in Zig with a C ABI. It
takes an RGBA8 pixel buffer, samples it onto a caller-selected output grid,
reduces the sampled colors to a limited palette, and returns an opaque RGBA8
buffer. It processes pixel buffers rather than opening image files, so decoding
and encoding are handled by the calling application.

Licensed under the [Mozilla Public License 2.0](LICENSE).

<p align="center">
  <img
    src="test_sources/output/preview.png"
    alt="Preview"
    width="60%"
  />
</p>

## Conversion

The conversion has three stages:

1. **Sampling** maps the source image to the requested output width and height.
   Nearest sampling selects a source pixel for each output pixel and is the
   default. Area sampling combines the covered source pixels, weighting color
   by alpha.
2. **Palette reduction** groups sampled colors into a palette and maps each
   output pixel to its nearest palette color.
3. **Cluster cleanup**, enabled by default, replaces isolated pixels when a
   sufficiently large group of nearby pixels has a similar color. Strong
   color differences are left alone.

Transparent pixels are composited onto the configured background before
palette reduction. The default background is black, and every output pixel has
alpha 255.

## Options

Initialize `madeitpx_options` with `madeitpx_options_init` to get the defaults,
then change the fields you need.

| Option | Behavior |
|---|---|
| `preset` | Selects a default palette limit: balanced (32), detail (64), or bold (16) colors. |
| `palette_colors` | Overrides the preset limit with a value from 2 to 64; zero uses the preset. |
| `sample_mode` | Chooses nearest or area sampling. Defaults to nearest. |
| `background_rgb` | Sets the opaque compositing color as `0xRRGGBB`. Defaults to black. |
| `cluster_cleanup` | Enables (`1`) or disables (`0`) cleanup of isolated, similar-colored pixels. Defaults to enabled. |

## C interface

The public declarations are in [`include/madeitpx.h`](include/madeitpx.h).
`madeitpx_convert_rgba8` accepts top-to-bottom RGBA8 input, its dimensions and
byte stride, the requested output dimensions, options, and a caller-provided
output buffer. The input stride may include padding; output is tightly packed.
Use `madeitpx_get_output_size` to determine the required output capacity.

The caller owns both buffers, and they must not overlap. The API reports
invalid arguments, undersized buffers, size overflow, and allocation failure
through `madeitpx_status`.

## .NET binding

The [`MadeIt.PixelArt` binding](bindings/dotnet/src/MadeIt.PixelArt) targets
.NET Framework 4.6.2, .NET Standard 2.0, .NET Standard 2.1, and .NET 10.0. Its
NuGet package includes native libraries for Windows, Linux (glibc), and macOS
on x64 and ARM64.

## Node.js binding

The [`@madeit/pixelart` package](bindings/node) wraps the native C ABI and
requires a separately built `madeitpx` shared library for the current platform
and architecture.

## Python binding

The [`madeitpx` package](bindings/python) installs with pip and includes native
libraries for Windows, Linux (glibc), and macOS on x64 and ARM64.

## Rust binding

The [`madeitpx` crate](bindings/rust) wraps the native C ABI and includes
libraries for Windows, Linux (glibc), and macOS on x64 and ARM64.

## Validation images

The [`test_sources/test-patterns`](test_sources/test-patterns) directory
contains images for checking sampling, palette limits, alpha compositing,
cleanup, and unusual dimensions. The comparisons below show each source with
every preset and sampling mode.

## Test-source results

<!-- generated-test-results:start -->

<details>
<summary>01_hue_gradient.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/01_hue_gradient--balanced-nearest.png"><img src="test_sources/output/01_hue_gradient--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/01_hue_gradient--balanced-area.png"><img src="test_sources/output/01_hue_gradient--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/01_hue_gradient--detail-nearest.png"><img src="test_sources/output/01_hue_gradient--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/01_hue_gradient--detail-area.png"><img src="test_sources/output/01_hue_gradient--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/01_hue_gradient--bold-nearest.png"><img src="test_sources/output/01_hue_gradient--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/01_hue_gradient--bold-area.png"><img src="test_sources/output/01_hue_gradient--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>02_gray_ramps.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/02_gray_ramps--balanced-nearest.png"><img src="test_sources/output/02_gray_ramps--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/02_gray_ramps--balanced-area.png"><img src="test_sources/output/02_gray_ramps--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/02_gray_ramps--detail-nearest.png"><img src="test_sources/output/02_gray_ramps--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/02_gray_ramps--detail-area.png"><img src="test_sources/output/02_gray_ramps--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/02_gray_ramps--bold-nearest.png"><img src="test_sources/output/02_gray_ramps--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/02_gray_ramps--bold-area.png"><img src="test_sources/output/02_gray_ramps--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>03_swatches_64_colors.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/03_swatches_64_colors--balanced-nearest.png"><img src="test_sources/output/03_swatches_64_colors--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/03_swatches_64_colors--balanced-area.png"><img src="test_sources/output/03_swatches_64_colors--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/03_swatches_64_colors--detail-nearest.png"><img src="test_sources/output/03_swatches_64_colors--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/03_swatches_64_colors--detail-area.png"><img src="test_sources/output/03_swatches_64_colors--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/03_swatches_64_colors--bold-nearest.png"><img src="test_sources/output/03_swatches_64_colors--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/03_swatches_64_colors--bold-area.png"><img src="test_sources/output/03_swatches_64_colors--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>04_near_duplicate_colors.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/04_near_duplicate_colors--balanced-nearest.png"><img src="test_sources/output/04_near_duplicate_colors--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/04_near_duplicate_colors--balanced-area.png"><img src="test_sources/output/04_near_duplicate_colors--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/04_near_duplicate_colors--detail-nearest.png"><img src="test_sources/output/04_near_duplicate_colors--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/04_near_duplicate_colors--detail-area.png"><img src="test_sources/output/04_near_duplicate_colors--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/04_near_duplicate_colors--bold-nearest.png"><img src="test_sources/output/04_near_duplicate_colors--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/04_near_duplicate_colors--bold-area.png"><img src="test_sources/output/04_near_duplicate_colors--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>05_alpha_ramps.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/05_alpha_ramps--balanced-nearest.png"><img src="test_sources/output/05_alpha_ramps--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/05_alpha_ramps--balanced-area.png"><img src="test_sources/output/05_alpha_ramps--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/05_alpha_ramps--detail-nearest.png"><img src="test_sources/output/05_alpha_ramps--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/05_alpha_ramps--detail-area.png"><img src="test_sources/output/05_alpha_ramps--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/05_alpha_ramps--bold-nearest.png"><img src="test_sources/output/05_alpha_ramps--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/05_alpha_ramps--bold-area.png"><img src="test_sources/output/05_alpha_ramps--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>06_alpha_soft_circle.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/06_alpha_soft_circle--balanced-nearest.png"><img src="test_sources/output/06_alpha_soft_circle--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/06_alpha_soft_circle--balanced-area.png"><img src="test_sources/output/06_alpha_soft_circle--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/06_alpha_soft_circle--detail-nearest.png"><img src="test_sources/output/06_alpha_soft_circle--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/06_alpha_soft_circle--detail-area.png"><img src="test_sources/output/06_alpha_soft_circle--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/06_alpha_soft_circle--bold-nearest.png"><img src="test_sources/output/06_alpha_soft_circle--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/06_alpha_soft_circle--bold-area.png"><img src="test_sources/output/06_alpha_soft_circle--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>07_checkerboards_1_2_4_8px.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/07_checkerboards_1_2_4_8px--balanced-nearest.png"><img src="test_sources/output/07_checkerboards_1_2_4_8px--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/07_checkerboards_1_2_4_8px--balanced-area.png"><img src="test_sources/output/07_checkerboards_1_2_4_8px--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/07_checkerboards_1_2_4_8px--detail-nearest.png"><img src="test_sources/output/07_checkerboards_1_2_4_8px--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/07_checkerboards_1_2_4_8px--detail-area.png"><img src="test_sources/output/07_checkerboards_1_2_4_8px--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/07_checkerboards_1_2_4_8px--bold-nearest.png"><img src="test_sources/output/07_checkerboards_1_2_4_8px--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/07_checkerboards_1_2_4_8px--bold-area.png"><img src="test_sources/output/07_checkerboards_1_2_4_8px--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>08_color_stripes_fine.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/08_color_stripes_fine--balanced-nearest.png"><img src="test_sources/output/08_color_stripes_fine--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/08_color_stripes_fine--balanced-area.png"><img src="test_sources/output/08_color_stripes_fine--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/08_color_stripes_fine--detail-nearest.png"><img src="test_sources/output/08_color_stripes_fine--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/08_color_stripes_fine--detail-area.png"><img src="test_sources/output/08_color_stripes_fine--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/08_color_stripes_fine--bold-nearest.png"><img src="test_sources/output/08_color_stripes_fine--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/08_color_stripes_fine--bold-area.png"><img src="test_sources/output/08_color_stripes_fine--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>09_isolated_pixels_cleanup.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/09_isolated_pixels_cleanup--balanced-nearest.png"><img src="test_sources/output/09_isolated_pixels_cleanup--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/09_isolated_pixels_cleanup--balanced-area.png"><img src="test_sources/output/09_isolated_pixels_cleanup--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/09_isolated_pixels_cleanup--detail-nearest.png"><img src="test_sources/output/09_isolated_pixels_cleanup--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/09_isolated_pixels_cleanup--detail-area.png"><img src="test_sources/output/09_isolated_pixels_cleanup--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/09_isolated_pixels_cleanup--bold-nearest.png"><img src="test_sources/output/09_isolated_pixels_cleanup--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/09_isolated_pixels_cleanup--bold-area.png"><img src="test_sources/output/09_isolated_pixels_cleanup--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>10_noisy_gradient.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/10_noisy_gradient--balanced-nearest.png"><img src="test_sources/output/10_noisy_gradient--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/10_noisy_gradient--balanced-area.png"><img src="test_sources/output/10_noisy_gradient--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/10_noisy_gradient--detail-nearest.png"><img src="test_sources/output/10_noisy_gradient--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/10_noisy_gradient--detail-area.png"><img src="test_sources/output/10_noisy_gradient--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/10_noisy_gradient--bold-nearest.png"><img src="test_sources/output/10_noisy_gradient--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/10_noisy_gradient--bold-area.png"><img src="test_sources/output/10_noisy_gradient--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>11_lines_shapes_text.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/11_lines_shapes_text--balanced-nearest.png"><img src="test_sources/output/11_lines_shapes_text--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/11_lines_shapes_text--balanced-area.png"><img src="test_sources/output/11_lines_shapes_text--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/11_lines_shapes_text--detail-nearest.png"><img src="test_sources/output/11_lines_shapes_text--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/11_lines_shapes_text--detail-area.png"><img src="test_sources/output/11_lines_shapes_text--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/11_lines_shapes_text--bold-nearest.png"><img src="test_sources/output/11_lines_shapes_text--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/11_lines_shapes_text--bold-area.png"><img src="test_sources/output/11_lines_shapes_text--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>12_scene_sprite.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/12_scene_sprite--balanced-nearest.png"><img src="test_sources/output/12_scene_sprite--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/12_scene_sprite--balanced-area.png"><img src="test_sources/output/12_scene_sprite--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/12_scene_sprite--detail-nearest.png"><img src="test_sources/output/12_scene_sprite--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/12_scene_sprite--detail-area.png"><img src="test_sources/output/12_scene_sprite--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/12_scene_sprite--bold-nearest.png"><img src="test_sources/output/12_scene_sprite--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/12_scene_sprite--bold-area.png"><img src="test_sources/output/12_scene_sprite--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>13_plasma_photo_like.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/13_plasma_photo_like--balanced-nearest.png"><img src="test_sources/output/13_plasma_photo_like--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/13_plasma_photo_like--balanced-area.png"><img src="test_sources/output/13_plasma_photo_like--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/13_plasma_photo_like--detail-nearest.png"><img src="test_sources/output/13_plasma_photo_like--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/13_plasma_photo_like--detail-area.png"><img src="test_sources/output/13_plasma_photo_like--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/13_plasma_photo_like--bold-nearest.png"><img src="test_sources/output/13_plasma_photo_like--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/13_plasma_photo_like--bold-area.png"><img src="test_sources/output/13_plasma_photo_like--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>14_extreme_colors.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/14_extreme_colors--balanced-nearest.png"><img src="test_sources/output/14_extreme_colors--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/14_extreme_colors--balanced-area.png"><img src="test_sources/output/14_extreme_colors--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/14_extreme_colors--detail-nearest.png"><img src="test_sources/output/14_extreme_colors--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/14_extreme_colors--detail-area.png"><img src="test_sources/output/14_extreme_colors--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/14_extreme_colors--bold-nearest.png"><img src="test_sources/output/14_extreme_colors--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/14_extreme_colors--bold-area.png"><img src="test_sources/output/14_extreme_colors--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>15_odd_size_1000x3.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/15_odd_size_1000x3--balanced-nearest.png"><img src="test_sources/output/15_odd_size_1000x3--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_1000x3--balanced-area.png"><img src="test_sources/output/15_odd_size_1000x3--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/15_odd_size_1000x3--detail-nearest.png"><img src="test_sources/output/15_odd_size_1000x3--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_1000x3--detail-area.png"><img src="test_sources/output/15_odd_size_1000x3--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/15_odd_size_1000x3--bold-nearest.png"><img src="test_sources/output/15_odd_size_1000x3--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_1000x3--bold-area.png"><img src="test_sources/output/15_odd_size_1000x3--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>15_odd_size_100x1.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/15_odd_size_100x1--balanced-nearest.png"><img src="test_sources/output/15_odd_size_100x1--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_100x1--balanced-area.png"><img src="test_sources/output/15_odd_size_100x1--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/15_odd_size_100x1--detail-nearest.png"><img src="test_sources/output/15_odd_size_100x1--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_100x1--detail-area.png"><img src="test_sources/output/15_odd_size_100x1--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/15_odd_size_100x1--bold-nearest.png"><img src="test_sources/output/15_odd_size_100x1--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_100x1--bold-area.png"><img src="test_sources/output/15_odd_size_100x1--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>15_odd_size_1x1.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/15_odd_size_1x1--balanced-nearest.png"><img src="test_sources/output/15_odd_size_1x1--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_1x1--balanced-area.png"><img src="test_sources/output/15_odd_size_1x1--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/15_odd_size_1x1--detail-nearest.png"><img src="test_sources/output/15_odd_size_1x1--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_1x1--detail-area.png"><img src="test_sources/output/15_odd_size_1x1--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/15_odd_size_1x1--bold-nearest.png"><img src="test_sources/output/15_odd_size_1x1--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_1x1--bold-area.png"><img src="test_sources/output/15_odd_size_1x1--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>15_odd_size_1x100.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/15_odd_size_1x100--balanced-nearest.png"><img src="test_sources/output/15_odd_size_1x100--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_1x100--balanced-area.png"><img src="test_sources/output/15_odd_size_1x100--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/15_odd_size_1x100--detail-nearest.png"><img src="test_sources/output/15_odd_size_1x100--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_1x100--detail-area.png"><img src="test_sources/output/15_odd_size_1x100--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/15_odd_size_1x100--bold-nearest.png"><img src="test_sources/output/15_odd_size_1x100--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_1x100--bold-area.png"><img src="test_sources/output/15_odd_size_1x100--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>15_odd_size_255x257.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/15_odd_size_255x257--balanced-nearest.png"><img src="test_sources/output/15_odd_size_255x257--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_255x257--balanced-area.png"><img src="test_sources/output/15_odd_size_255x257--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/15_odd_size_255x257--detail-nearest.png"><img src="test_sources/output/15_odd_size_255x257--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_255x257--detail-area.png"><img src="test_sources/output/15_odd_size_255x257--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/15_odd_size_255x257--bold-nearest.png"><img src="test_sources/output/15_odd_size_255x257--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_255x257--bold-area.png"><img src="test_sources/output/15_odd_size_255x257--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>15_odd_size_2x2.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/15_odd_size_2x2--balanced-nearest.png"><img src="test_sources/output/15_odd_size_2x2--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_2x2--balanced-area.png"><img src="test_sources/output/15_odd_size_2x2--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/15_odd_size_2x2--detail-nearest.png"><img src="test_sources/output/15_odd_size_2x2--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_2x2--detail-area.png"><img src="test_sources/output/15_odd_size_2x2--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/15_odd_size_2x2--bold-nearest.png"><img src="test_sources/output/15_odd_size_2x2--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_2x2--bold-area.png"><img src="test_sources/output/15_odd_size_2x2--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>15_odd_size_37x23.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/15_odd_size_37x23--balanced-nearest.png"><img src="test_sources/output/15_odd_size_37x23--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_37x23--balanced-area.png"><img src="test_sources/output/15_odd_size_37x23--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/15_odd_size_37x23--detail-nearest.png"><img src="test_sources/output/15_odd_size_37x23--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_37x23--detail-area.png"><img src="test_sources/output/15_odd_size_37x23--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/15_odd_size_37x23--bold-nearest.png"><img src="test_sources/output/15_odd_size_37x23--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_37x23--bold-area.png"><img src="test_sources/output/15_odd_size_37x23--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>15_odd_size_7x513.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/15_odd_size_7x513--balanced-nearest.png"><img src="test_sources/output/15_odd_size_7x513--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_7x513--balanced-area.png"><img src="test_sources/output/15_odd_size_7x513--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/15_odd_size_7x513--detail-nearest.png"><img src="test_sources/output/15_odd_size_7x513--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_7x513--detail-area.png"><img src="test_sources/output/15_odd_size_7x513--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/15_odd_size_7x513--bold-nearest.png"><img src="test_sources/output/15_odd_size_7x513--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/15_odd_size_7x513--bold-area.png"><img src="test_sources/output/15_odd_size_7x513--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<details>
<summary>16_alpha_checker_over_plasma.png</summary>

<table>
<thead><tr><th>Preset</th><th>Nearest</th><th>Area</th></tr></thead>
<tbody>
<tr><th>balanced (32 colors)</th>
<td><a href="test_sources/output/16_alpha_checker_over_plasma--balanced-nearest.png"><img src="test_sources/output/16_alpha_checker_over_plasma--balanced-nearest.png" alt="balanced / nearest / max 32 colors" width="160"></a></td>
<td><a href="test_sources/output/16_alpha_checker_over_plasma--balanced-area.png"><img src="test_sources/output/16_alpha_checker_over_plasma--balanced-area.png" alt="balanced / area / max 32 colors" width="160"></a></td>
</tr>
<tr><th>detail (64 colors)</th>
<td><a href="test_sources/output/16_alpha_checker_over_plasma--detail-nearest.png"><img src="test_sources/output/16_alpha_checker_over_plasma--detail-nearest.png" alt="detail / nearest / max 64 colors" width="160"></a></td>
<td><a href="test_sources/output/16_alpha_checker_over_plasma--detail-area.png"><img src="test_sources/output/16_alpha_checker_over_plasma--detail-area.png" alt="detail / area / max 64 colors" width="160"></a></td>
</tr>
<tr><th>bold (16 colors)</th>
<td><a href="test_sources/output/16_alpha_checker_over_plasma--bold-nearest.png"><img src="test_sources/output/16_alpha_checker_over_plasma--bold-nearest.png" alt="bold / nearest / max 16 colors" width="160"></a></td>
<td><a href="test_sources/output/16_alpha_checker_over_plasma--bold-area.png"><img src="test_sources/output/16_alpha_checker_over_plasma--bold-area.png" alt="bold / area / max 16 colors" width="160"></a></td>
</tr>
</tbody>
</table>

</details>

<!-- generated-test-results:end -->
