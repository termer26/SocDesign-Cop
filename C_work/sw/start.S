.section .text.start,"ax",@progbits
.globl _start
_start:
    lui sp, 0xa0080
    addi sp, sp, -16
    la t0, trap_entry
    csrw mtvec, t0
    call main
1:  j 1b
trap_entry:
    lui t0, 0xa0060
    csrr t1, mcause
    sw t1, 16(t0)
    li t1, 0xbad2
    sw t1, 12(t0)
2:  j 2b
