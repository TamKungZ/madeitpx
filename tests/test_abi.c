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

    puts("C ABI OK");
    return 0;
}
