// 全局宏定义 —— 七级流水 RISC-V RV32I + M + Zicsr + Zba + Trap
`ifndef __DEFINES_VH__
`define __DEFINES_VH__
// ---- 宏操作融合开关(取指部分用)----
`ifndef FUSE_EN         //fuse（融合），macro-fuse（宏操作融合）
`define FUSE_EN 1'b1   // 宏操作融合总开关,置 0 回退纯双发取指
`endif
`ifndef FUSE_F2
`define FUSE_F2 1'b1   // F2 移位加融合单独开关,时序不利时置 0
`endif

// ===== ALU 操作码（5 bit）=====
`define ALU_ADD    5'd0   // 加法（ADD/ADDI/Load/Store地址/JAL/JALR）
`define ALU_SUB    5'd1   // 减法（SUB）
`define ALU_AND    5'd2   // 按位与
`define ALU_OR     5'd3   // 按位或
`define ALU_XOR    5'd4   // 按位异或
`define ALU_SLL    5'd5   // 逻辑左移
`define ALU_SRL    5'd6   // 逻辑右移
`define ALU_SRA    5'd7   // 算术右移
`define ALU_SLT    5'd8   // 有符号小于比较
`define ALU_SLTU   5'd9   // 无符号小于比较
`define ALU_LUI    5'd10  // 直通B口（LUI：alu_out = imm）
`define ALU_AUIPC  5'd11  // A+B（AUIPC：alu_a=pc, alu_b=imm）
// ---- M 扩展（新增 8 条）----
`define ALU_MUL    5'd12  // 乘法低32位
`define ALU_MULH   5'd13  // 乘法高32位（有符号×有符号）
`define ALU_MULHSU 5'd14  // 乘法高32位（有符号×无符号）
`define ALU_MULHU  5'd15  // 乘法高32位（无符号×无符号）
`define ALU_DIV    5'd16  // 有符号除法
`define ALU_DIVU   5'd17  // 无符号除法（除零返回全1）
`define ALU_REM    5'd18  // 有符号取余
`define ALU_REMU   5'd19  // 无符号取余（除零返回被除数）
// ---- Zicsr / Trap 走 ALU 直通 ----
`define ALU_CSR    5'd20  // CSR 读出值直通到 rd
// ---- 现场 B 扩展槽位（编码到 31，留给比赛当天）----
`define ALU_BEXT0  5'd24
`define ALU_BEXT1  5'd25
`define ALU_BEXT2  5'd26
`define ALU_BEXT3  5'd27
// 5'd28~5'd31 继续保留

// ===== CSR 写入方式 =====
`define CSR_OP_NONE 2'd0
`define CSR_OP_RW   2'd1  // csrrw / csrrwi：直接写 src
`define CSR_OP_RS   2'd2  // csrrs / csrrsi：写 old | src
`define CSR_OP_RC   2'd3  // csrrc / csrrci：写 old & ~src

// ===== Trap 原因码（mcause Exception Code 字段）=====
`define CAUSE_ECALL_M 32'd11   // M 模式 ecall

// ===== M 模式 CSR 地址 =====
`define CSR_MSTATUS    12'h300   // RISC-V 特权规范规定,参考https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html
`define CSR_MTVEC      12'h305
`define CSR_MSCRATCH   12'h340
`define CSR_MEPC       12'h341
`define CSR_MCAUSE     12'h342

// ===== 性能计数器 CSR（M 模式 RW + U 模式 RO 影子） =====
`define CSR_MCYCLE     12'hB00
`define CSR_MINSTRET   12'hB02
`define CSR_MCYCLEH    12'hB80
`define CSR_MINSTRETH  12'hB82
`define CSR_CYCLE      12'hC00   // rdcycle  -> 同 mcycle
`define CSR_INSTRET    12'hC02   // rdinstret -> 同 minstret
`define CSR_CYCLEH     12'hC80
`define CSR_INSTRETH   12'hC82

// 写回来源选择
`define WB_ALU  2'd0     // 写回ALU结果
`define WB_MEM  2'd1     // 写回Load数据（mem_rdata）
`define WB_PC4  2'd2     // 写回PC+4（JAL/JALR返回地址）

// 转发来源选择(3bit)
`define FWD_NONE 3'd0    // 不转发,用寄存器堆读出值
`define FWD_EX2  3'd1    // EX2 的 ALU 结果(e2_alu_out)
`define FWD_MEM1 3'd2    // MEM1 预选寄存器(mem1_fwd_reg)
`define FWD_WB_ALU 3'd3  // WB 的 ALU 结果(w_alu_out)
// 3'd4 空置(原 FWD_WB,已删)
`define FWD_EX2P 3'd5    // EX2 的 pc+4(jal/jalr 链接值)
`define FWD_WB_MEM 3'd6  // WB 的 Load 数据(w_mem_rdata)
`define FWD_WB_PC4 3'd7  // WB 的 pc+4(w_pc4)

// 访存宽度
`define MEM_BYTE 2'd0    // 字节（8位）
`define MEM_HALF 2'd1    // 半字（16位）
`define MEM_WORD 2'd2    // 字（32位）

// 常用指令
`define INST_NOP 32'h00000013   // NOP：ADDI x0, x0, 0

`endif
