# madeitpx

Native image-processing library written in Zig with a C ABI.

The current API converts RGBA8 buffers to a caller-selected pixel grid, groups
colors into a limited palette, and returns opaque RGBA8 pixels. It provides
balanced, detail, and bold presets, a configurable palette size, a background
color for transparent input, and area or nearest sampling.

Input is top-to-bottom, with an explicit byte stride. Output is tightly packed
RGBA8. `madeitpx_options_init` supplies the balanced preset (32 colors), nearest
sampling, and a black background. Set `preset` to `MADEITPX_PRESET_DETAIL` for
64 colors or `MADEITPX_PRESET_BOLD` for 16; `palette_colors` overrides those
limits with a value from 2 through 64. `background_rgb` is `0xRRGGBB`.
`cluster_cleanup` defaults to 1 and replaces isolated, similar-color pixels
with a dominant neighboring color while retaining high-contrast details.
Transparent input is composited onto that background; output alpha is 255.
The caller owns both buffers; they must not overlap.

```sh
zig build
zig build test
```

The public header is in `include/madeitpx.h`; build outputs are in `zig-out/`.
