/* link.ld —— 自研 7 级流水 RV32IM CPU（Harvard：IROM 不可数据访问）
 *   IROM @ 0x00000000  (sim 64KB / FPGA 16KB)  -- 仅 .text
 *   DRAM @ 0x80100000  (256KB)                 -- .rodata + .data + .bss + heap + stack
 *
 *   stack 顶端 = DRAM 顶端 (0x80140000)
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    IROM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    DRAM (rwx) : ORIGIN = 0x80100000, LENGTH = 256K
}

PROVIDE(__STACK_SIZE = 8K);
PROVIDE(__HEAP_SIZE  = 16K);

SECTIONS
{
    /* -------- 代码段：仅 .text 在 IROM -------- */
    .text : ALIGN(4) {
        _stext = .;
        KEEP(*(.text.init))         /* crt0 _start 入口必须在最前 */
        *(.text)
        *(.text.*)
        . = ALIGN(4);
        _etext = .;
    } > IROM

    /* -------- 只读数据：放 DRAM 因为 CPU 不能从 IROM 做 load -------- */
    .rodata : ALIGN(4) {
        _srodata = .;
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)
        . = ALIGN(4);
        _erodata = .;
    } > DRAM

    /* -------- 已初始化数据 -------- */
    .data : ALIGN(4) {
        _sdata = .;
        *(.data)
        *(.data.*)
        . = ALIGN(8);
        PROVIDE(__global_pointer$ = . + 0x800);
        *(.sdata)
        *(.sdata.*)
        *(.gnu.linkonce.s.*)
        . = ALIGN(4);
        _edata = .;
    } > DRAM

    /* -------- BSS -------- */
    .bss (NOLOAD) : ALIGN(4) {
        _sbss = .;
        *(.sbss)
        *(.sbss.*)
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > DRAM

    /* -------- heap -------- */
    . = ALIGN(8);
    _end = .;            /* _sbrk 起点 */
    PROVIDE(end = .);

    .heap (NOLOAD) : ALIGN(8) {
        _sheap = .;
        . = . + __HEAP_SIZE;
        . = ALIGN(8);
        _eheap = .;
    } > DRAM

    /* -------- stack（DRAM 顶部） -------- */
    .stack ORIGIN(DRAM) + LENGTH(DRAM) - __STACK_SIZE (NOLOAD) : ALIGN(16) {
        _sstack = .;
        . = . + __STACK_SIZE;
        . = ALIGN(16);
        _estack = .;
    } > DRAM

    /DISCARD/ : {
        *(.eh_frame)
        *(.eh_frame_hdr)
        *(.comment)
        *(.note.*)
        *(.debug_*)
    }
}
