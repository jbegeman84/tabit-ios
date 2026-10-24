#ifndef CTABIT_COMPRESSION_H
#define CTABIT_COMPRESSION_H

#include <stddef.h>
#include <stdint.h>

/// Inflates one RFC 1950 zlib stream.
///
/// On success, the caller owns `output` and must release it with
/// `tabit_free`. `consumed` excludes bytes following the end of the stream.
int tabit_inflate_zlib(
    const uint8_t *input,
    size_t input_length,
    uint8_t **output,
    size_t *output_length,
    size_t *consumed
);

void tabit_free(void *pointer);

#endif
