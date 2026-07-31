#ifndef DPI_BRIDGE_H
#define DPI_BRIDGE_H

#include "dpi_types.h"

#ifdef __cplusplus
extern "C" {
#endif

void dpi_gem5_init(const char* elf_path);
int  dpi_gem5_step_and_compare(const generic_commit_t* rtl_commit);

#ifdef __cplusplus
}
#endif

#endif
