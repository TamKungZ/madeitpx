# madeitpx

Native image-processing library written in Zig with a C ABI.

The current API accepts RGBA8 buffers and resamples them to caller-selected
dimensions using area-weighted averaging. This is an initial baseline, not a
complete pixel-art conversion pipeline.

Input is top-to-bottom, tightly packed by pixel within each row, with an
explicit byte stride. Output is tightly packed RGBA8. Averaging uses
premultiplied alpha. The caller owns both buffers; they must not overlap.

```sh
zig build
zig build test
```

The public header is in `include/madeitpx.h`; build outputs are in `zig-out/`.
