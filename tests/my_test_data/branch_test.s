# -------------------------------------------------------------------------
# RISC-V 32I Branch Prediction Test
# 禁用 M 扩展 (无 mul/div/rem)
# -------------------------------------------------------------------------

.section .text
.globl _start

_start:
    # -------------------------------------------------------------------------
    # 1. 基础向后跳转测试 (Testing BHT/2-bit Counter)
    # 模式: TTTTT...TN (19次成功跳转，1次失败)
    # -------------------------------------------------------------------------
    addi t0, x0, 20      # 循环 20 次
loop_simple:
    addi t0, t0, -1
    bne t0, x0, loop_simple # 向后跳转。预测器应快速学习并预测 Taken


    # -------------------------------------------------------------------------
    # 2. 交替模式测试 (Testing Global History / Gshare)
    # 模式: T N T N T N ... (跳转/不跳转交替)
    # -------------------------------------------------------------------------
    addi t0, x0, 20      # 迭代 20 次
    addi t1, x0, 1       # 掩码
loop_parity:
    and t2, t0, t1       # 检查最低位
    beq t2, x0, is_even  # 如果是偶数跳转到 is_even (Taken)
    # 奇数路径 (Not Taken)
    addi x0, x0, 0       # nop
    j next_parity
is_even:
    addi x0, x0, 0       # nop
next_parity:
    addi t0, t0, -1
    bne t0, x0, loop_parity


    # -------------------------------------------------------------------------
    # 3. 周期性模式测试 (Testing Pattern History - TTN Pattern)
    # 模式: Taken, Taken, Not-Taken (通过计数器模拟)
    # -------------------------------------------------------------------------
    addi t0, x0, 30      # 总计数
    addi t1, x0, 0       # 阶段计数器 (0, 1, 2)
loop_pattern:
    addi t1, t1, 1
    addi t2, x0, 3
    blt t1, t2, is_taken # 如果 t1 < 3 则跳转 (模拟 T, T, N 模式)
    addi t1, x0, 0       # 计数器重置 (第3次不跳转)
    j pattern_end
is_taken:
    addi x0, x0, 0
pattern_end:
    addi t0, t0, -1
    bne t0, x0, loop_pattern


    # -------------------------------------------------------------------------
    # 4. 分支目标缓冲测试 (Testing BTB - Branch Target Buffer)
    # 通过 jalr 频繁切换目标地址，测试 PC 预测能力
    # -------------------------------------------------------------------------
    addi t0, x0, 20
    # 加载目标地址到寄存器 (RV32I 使用 lui/addi 模拟 la)
    lui t2, %hi(target_1)
    addi t2, t2, %lo(target_1)
    lui t3, %hi(target_2)
    addi t3, t3, %lo(target_2)

loop_btb:
    andi t1, t0, 1
    beq t1, x0, call_2
    jalr ra, t2, 0       # 跳转到 target_1
    j btb_done
call_2:
    jalr ra, t3, 0       # 跳转到 target_2
btb_done:
    addi t0, t0, -1
    bne t0, x0, loop_btb

    # -------------------------------------------------------------------------
    # 5. 结束
    # -------------------------------------------------------------------------
finish:
    # 如果是仿真环境，可以通过向特定地址写值或陷入死循环
    j finish

# --- 子程序目标 (必须对齐，防止取指跨行) ---
.align 4
target_1:
    addi a0, x0, 1
    jalr x0, ra, 0       # ret

.align 4
target_2:
    addi a0, x0, 2
    jalr x0, ra, 0       # ret