#include <stdint.h>
#include <stdio.h>
#include "madeitpx.h"

int main(void) {
    madeitpx_options options;
    const uint8_t input[] = {255, 0, 0, 0, 0, 0, 255, 255};
    uint8_t output[4];
    size_t output_size = 0;

    if (madeitpx_version() != 0x00010000u) return 1;
    if (madeitpx_options_init(&options) != MADEITPX_OK) return 2;
    if (options.struct_size != sizeof(options) ||
        options.sample_mode != MADEITPX_SAMPLE_NEAREST ||
        options.cluster_cleanup != 1)
        return 3;
    options.sample_mode = MADEITPX_SAMPLE_AREA;
    if (madeitpx_get_output_size(1, 1, &output_size) != MADEITPX_OK || output_size != 4) return 4;
    if (madeitpx_convert_rgba8(
            input, sizeof(input), 2, 1, 8, 1, 1, &options, output, sizeof(output)
        ) != MADEITPX_OK)
        return 5;
    if (output[0] != 0 || output[1] != 0 || output[2] != 128 || output[3] != 255) return 6;

    {
        madeitpx_pixelart_options detail;
        const uint8_t pixel[] = {10, 20, 30, 255};
        uint8_t result[4];
        if (madeitpx_pixelart_options_init(&detail) != MADEITPX_OK ||
            detail.struct_size != sizeof(detail) || detail.version != 2)
            return 7;
        detail.color_tolerance = 99;
        if (madeitpx_pixelart_options_reset_field(&detail, MADEITPX_PIXELART_FIELD_COLOR_TOLERANCE) != MADEITPX_OK ||
            detail.color_tolerance != 14)
            return 8;
        if (madeitpx_convert_pixelart_rgba8(
                pixel, sizeof(pixel), 1, 1, 4, 1, 1, &options, &detail, result, sizeof(result)
            ) != MADEITPX_OK ||
            result[0] != 10 || result[1] != 20 || result[2] != 30 || result[3] != 255)
            return 9;
    }

    puts("C ABI OK");
    return 0;
}
