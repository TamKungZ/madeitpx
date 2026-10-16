#ifndef MADEITPX_H
#define MADEITPX_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum madeitpx_status {
    MADEITPX_OK = 0,
    MADEITPX_INVALID_ARGUMENT = 1,
    MADEITPX_BUFFER_TOO_SMALL = 2,
    MADEITPX_SIZE_OVERFLOW = 3,
    MADEITPX_OUT_OF_MEMORY = 4
} madeitpx_status;

typedef enum madeitpx_preset {
    MADEITPX_PRESET_BALANCED = 0,
    MADEITPX_PRESET_DETAIL = 1,
    MADEITPX_PRESET_BOLD = 2
} madeitpx_preset;

typedef enum madeitpx_sample_mode {
    MADEITPX_SAMPLE_AREA = 0,
    MADEITPX_SAMPLE_NEAREST = 1
} madeitpx_sample_mode;

typedef struct madeitpx_options {
    uint32_t struct_size;
    uint32_t preset;
    uint32_t palette_colors;
    uint32_t background_rgb;
    uint32_t sample_mode;
    uint32_t cluster_cleanup;
    uint32_t reserved;
} madeitpx_options;

uint32_t madeitpx_version(void);
madeitpx_status madeitpx_options_init(madeitpx_options *options);
madeitpx_status madeitpx_get_output_size(
    uint32_t target_width,
    uint32_t target_height,
    size_t *output_size
);
madeitpx_status madeitpx_convert_rgba8(
    const uint8_t *input,
    size_t input_size,
    uint32_t input_width,
    uint32_t input_height,
    size_t input_stride,
    uint32_t target_width,
    uint32_t target_height,
    const madeitpx_options *options,
    uint8_t *output,
    size_t output_capacity
);

#ifdef __cplusplus
}
#endif

#endif
