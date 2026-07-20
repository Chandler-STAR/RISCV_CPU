/* crt0.S —— RV32IM 启动代码（Harvard：.rodata/.data 已在 DRAM，不需要拷贝）
 *   1. 设置 sp / gp
 *   2. 清 .bss
 *   3. 调用 main()
 *   4. 返回后写魔法 EXIT 触发仿真结束
 */
    .section .text.init, "ax"
    .global _start
    .type _start, @function

_start:
    /* gp = __global_pointer$ */
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    /* sp = _estack */
    la      sp, _estack

    /* ---- zero .bss ---- */
    la      a0, _sbss
    la      a1, _ebss
    beq     a0, a1, 2f
1:  sw      zero, 0(a0)
    addi    a0, a0, 4
    bltu    a0, a1, 1b
2:

    /* ---- a0 = 0, a1 = 0（无 argc / argv）---- */
    li      a0, 0
    li      a1, 0
    call    main

    /* 若 main 返回（CoreMark 用 portable_fini 提前退） */
    mv      a0, zero
    call    _exit

3:  j       3b
    .size _start, .-_start
