// 全局宏定义 7级流水线 RISC-V RV32I
`ifndef __DEFINES_VH__
`define __DEFINES_VH__

// ALU 操作码
`define ALU_ADD   4'd0   // 加法（ADD/ADDI/Load/Store地址/JAL/JALR）
`define ALU_SUB   4'd1   // 减法（SUB）
`define ALU_AND   4'd2   // 按位与
`define ALU_OR    4'd3   // 按位或
`define ALU_XOR   4'd4   // 按位异或
`define ALU_SLL   4'd5   // 逻辑左移
`define ALU_SRL   4'd6   // 逻辑右移
`define ALU_SRA   4'd7   // 算术右移
`define ALU_SLT   4'd8   // 有符号小于比较
`define ALU_SLTU  4'd9   // 无符号小于比较
`define ALU_LUI   4'd10  // 直通B口（LUI：alu_out = imm）
`define ALU_AUIPC 4'd11  // A+B（AUIPC：alu_a=pc, alu_b=imm）

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
