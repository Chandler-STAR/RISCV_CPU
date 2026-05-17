// 全局宏定义 7级流水线 RISC-V RV32I + Zicsr + M + Trap + B扩展槽位
`ifndef __DEFINES_VH__
`define __DEFINES_VH__

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
`define ALU_MUL    5'd12
`define ALU_MULH   5'd13
`define ALU_MULHSU 5'd14
`define ALU_MULHU  5'd15
`define ALU_DIV    5'd16
`define ALU_DIVU   5'd17
`define ALU_REM    5'd18
`define ALU_REMU   5'd19
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
`define CSR_MSTATUS  12'h300
`define CSR_MTVEC    12'h305
`define CSR_MSCRATCH 12'h340
`define CSR_MEPC     12'h341
`define CSR_MCAUSE   12'h342

// 写回来源选择
`define WB_ALU  2'd0     // 写回ALU结果
`define WB_MEM  2'd1     // 写回Load数据（mem_rdata）
`define WB_PC4  2'd2     // 写回PC+4（JAL/JALR返回地址）

// 转发来源选择（3bit，5选1）
`define FWD_NONE 3'd0    // 不转发，使用寄存器文件读出值
`define FWD_EX2  3'd1    // 从EX2阶段转发（ex1_ex2_reg.alu_out）
`define FWD_MEM1 3'd2    // 从MEM1阶段转发（ex2_mem1_reg.alu_out）
`define FWD_MEM2 3'd3    // 从MEM2阶段转发（mem1_mem2_reg，含Load数据）
`define FWD_WB   3'd4    // 从WB阶段转发（wb_data）

// 访存宽度
`define MEM_BYTE 2'd0    // 字节（8位）
`define MEM_HALF 2'd1    // 半字（16位）
`define MEM_WORD 2'd2    // 字（32位）

// 常用指令
`define INST_NOP 32'h00000013   // NOP：ADDI x0, x0, 0

`endif
