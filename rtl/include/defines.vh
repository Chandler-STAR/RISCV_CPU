//全局定义宏文件
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
`define ALU_LUI   4'd10  // 直通 B（LUI，alu_out = imm）
`define ALU_AUIPC 4'd11  // A + B（AUIPC，alu_a=pc, alu_b=imm）

// 写回选择 
`define WB_ALU  2'd0   // 写回 ALU 结果
`define WB_MEM  2'd1   // 写回 Load 数据（mem_rdata）
`define WB_PC4  2'd2   // 写回 PC+4（JAL/JALR 返回地址）

// 前递选择 
`define FWD_NONE 2'd0  // 不前递，使用寄存器读出值
`define FWD_M    2'd1  // 从 EX/MEM 寄存器前递（alu_out）
`define FWD_W    2'd2  // 从 MEM/WB 寄存器前递（wd）

// 访存宽度 
`define MEM_BYTE 2'd0  // 字节（8位）
`define MEM_HALF 2'd1  // 半字（16位）
`define MEM_WORD 2'd2  // 字（32位）

//常用指令
`define INST_NOP 32'h00000013

`endif