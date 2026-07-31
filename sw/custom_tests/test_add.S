.text
.globl _start
_start:
    addi a0, zero, 5
    addi a1, zero, 3
    add  a2, a0, a1
    addi a3, zero, 0
loop:
    j loop
