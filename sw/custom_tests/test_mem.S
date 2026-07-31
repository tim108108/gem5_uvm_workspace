# test_mem.S — RISC-V RV32IMC memory test
# Tests word load/store, byte load/store, halfword load/store.

    .section .bss
    .align 4
    .globl mem_buf
mem_buf:
    .space 64                 # 64 bytes of BSS
    .size mem_buf, 64

    .section .text
    .globl _start

_start:
    # Use BSS buffer address for memory operations
    la sp, mem_buf + 32       # sp = &mem_buf[32]

    # Load test value 0x12345678 into a1
    lui a1, 0x12345
    addi a1, a1, 0x678       # a1 = 0x12345678

    # --- Word store + load ---
    sw a1, 0(sp)             # mem[sp] = 0x12345678
    lw a2, 0(sp)             # a2 = mem[sp] (= 0x12345678)

    # --- Byte store + load (use offset from sp) ---
    sb a1, -16(sp)           # byte at sp-16: 0x78
    sb a1, -15(sp)           # byte at sp-15: 0x56
    sb a1, -14(sp)           # byte at sp-14: 0x34
    sb a1, -13(sp)           # byte at sp-13: 0x12

    lb a3, -16(sp)           # a3 = sign-ext 0x78 (0x00000078)
    lb a4, -13(sp)           # a4 = sign-ext 0x12 (0x00000012)

    # --- Halfword store + load ---
    sh a1, -8(sp)            # halfword at sp-8 = 0x5678
    lhu a5, -8(sp)           # a5 = zero-ext 0x5678
    lh a6, -8(sp)            # a6 = sign-ext 0x5678 (positive)

    # --- Multi-store pattern ---
    addi a0, sp, -32         # base = sp - 32
    addi t0, zero, 0xAA
    sw t0, 0(a0)
    addi t0, zero, 0xBB
    sw t0, 4(a0)
    addi t0, zero, 0xCC
    sw t0, 8(a0)
    addi t0, zero, 0xDD
    sw t0, 12(a0)

    lw t0, 0(a0)
    lw t1, 4(a0)
    lw t2, 8(a0)
    lw t3, 12(a0)

    add a7, t0, t1           # a7 = 0xAA + 0xBB = 0x165
    add a7, a7, t2           # a7 += 0xCC = 0x231
    add a7, a7, t3           # a7 += 0xDD = 0x30E

loop:
    j loop
