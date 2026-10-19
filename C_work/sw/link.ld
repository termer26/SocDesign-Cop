ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0xa0070000, LENGTH = 64K }
SECTIONS {
    .text : { KEEP(*(.text.start)) *(.text*) *(.rodata*) } > RAM
    .data : { *(.sdata*) *(.data*) } > RAM
    .bss (NOLOAD) : { *(.bss*) *(.sbss*) *(COMMON) } > RAM
    /DISCARD/ : { *(.comment) *(.eh_frame*) *(.riscv.attributes) }
    ASSERT(SIZEOF(.text)+SIZEOF(.data)+SIZEOF(.bss)<0xf000,"Firmware overlaps stack")
}
