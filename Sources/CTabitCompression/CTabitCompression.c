#include "CTabitCompression.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

int tabit_inflate_zlib(
    const uint8_t *input,
    size_t input_length,
    uint8_t **output,
    size_t *output_length,
    size_t *consumed
) {
    if (!input || !output || !output_length || !consumed || input_length == 0) {
        return Z_STREAM_ERROR;
    }

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_length;

    int result = inflateInit(&stream);
    if (result != Z_OK) {
        return result;
    }

    size_t capacity = input_length < 4096 ? 4096 : input_length * 2;
    uint8_t *buffer = malloc(capacity);
    if (!buffer) {
        inflateEnd(&stream);
        return Z_MEM_ERROR;
    }

    do {
        if (stream.total_out == capacity) {
            if (capacity > SIZE_MAX / 2) {
                free(buffer);
                inflateEnd(&stream);
                return Z_MEM_ERROR;
            }
            capacity *= 2;
            uint8_t *larger_buffer = realloc(buffer, capacity);
            if (!larger_buffer) {
                free(buffer);
                inflateEnd(&stream);
                return Z_MEM_ERROR;
            }
            buffer = larger_buffer;
        }

        stream.next_out = buffer + stream.total_out;
        stream.avail_out = (uInt)(capacity - stream.total_out);
        result = inflate(&stream, Z_NO_FLUSH);
    } while (result == Z_OK);

    if (result != Z_STREAM_END) {
        free(buffer);
        inflateEnd(&stream);
        return result;
    }

    *output = buffer;
    *output_length = stream.total_out;
    *consumed = stream.total_in;
    inflateEnd(&stream);
    return Z_OK;
}

int tabit_deflate_zlib(
    const uint8_t *input,
    size_t input_length,
    uint8_t **output,
    size_t *output_length
) {
    if (!input || !output || !output_length || input_length > UINT_MAX) {
        return Z_STREAM_ERROR;
    }

    uLongf capacity = compressBound((uLong)input_length);
    uint8_t *buffer = malloc(capacity);
    if (!buffer) {
        return Z_MEM_ERROR;
    }

    int result = compress2(
        buffer,
        &capacity,
        input,
        (uLong)input_length,
        Z_BEST_COMPRESSION
    );
    if (result != Z_OK) {
        free(buffer);
        return result;
    }

    *output = buffer;
    *output_length = (size_t)capacity;
    return Z_OK;
}

uint32_t tabit_crc32(const uint8_t *input, size_t input_length) {
    return (uint32_t)crc32(0L, input, (uInt)input_length);
}

void tabit_free(void *pointer) {
    free(pointer);
}
