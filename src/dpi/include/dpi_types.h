#ifndef DPI_TYPES_H
#define DPI_TYPES_H

#ifdef __cplusplus
#include <cstdint>
#else
#include <stdint.h>
#endif

typedef struct __attribute__((packed)) {
    uint64_t pc;
    uint32_t instr_bytes;
    uint8_t  reg_write_en;
    uint8_t  reg_addr;
    uint64_t reg_data;
    uint8_t  is_mem_op;
    uint64_t mem_addr;
} generic_commit_t;

#endif
