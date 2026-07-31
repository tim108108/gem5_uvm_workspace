#!/bin/bash
# Convert RISC-V ELF to hex file for $readmemh
ELF=$1
HEX=$2
riscv64-unknown-elf-objcopy -O verilog "$ELF" "$HEX"
# Fallback: objcopy -O verilog may not work; use binary + od instead
if [ ! -s "$HEX" ] || [ "$(head -c 4 "$HEX")" = "" ]; then
    riscv64-unknown-elf-objcopy -O binary "$ELF" "${ELF}.bin"
    hexdump -v -e '"%08x\n"' "${ELF}.bin" > "$HEX"
    rm -f "${ELF}.bin"
fi
echo "Generated: $HEX"
