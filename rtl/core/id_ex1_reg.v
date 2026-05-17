`include "../include/defines.vh"
// ID→EX1 流水线寄存器

module id_ex1_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,              // 冲刷（load-use停顿 或 分支跳转）
    input  wire        stall,              // DRAM停顿时保持，防止指令重复锁存
    // 数据通路
    input  wire [31:0] pc_in,              // ID阶段PC
    input  wire [31:0] pc4_in,             // ID阶段PC+4
    input  wire [31:0] instr_in,           // ID阶段指令
    input  wire [31:0] rs1_in,             // 寄存器文件rs1读出值
    input  wire [31:0] rs2_in,             // 寄存器文件rs2读出值
    input  wire [31:0] imm_in,             // 立即数生成器输出
    input  wire [ 4:0] rd_addr_in,         // 目的寄存器地址
    // 控制信号
    input  wire        reg_we_in,          // 寄存器写使能
    input  wire        mem_we_in,          // 存储器写使能（Store）
    input  wire        mem_re_in,          // 存储器读使能（Load）
    input  wire        branch_in,          // 条件分支标志
    input  wire        jump_in,            // 无条件跳转标志（JAL/JALR）
    input  wire        alu_src_in,         // ALU B口选择：0=rs2, 1=立即数
    input  wire [ 1:0] wb_sel_in,          // 写回来源：ALU/MEM/PC4
    input  wire [ 4:0] alu_op_in,          // ALU操作码
    input  wire [ 1:0] mem_width_in,       // 访存宽度：字节/半字/字
    input  wire        mem_sign_in,        // Load符号扩展使能
    input  wire        predict_taken_in,   // 分支预测taken
    input  wire [31:0] predict_target_in,  // 分支预测target
    input  wire [ 1:0] instr_type_in,      // 输出到EX1阶段
    
    // Zicsr / Trap / M / B 扩展新增端口
    input  wire        is_csr_in,
    input  wire [ 1:0] csr_op_in,
    input  wire        csr_uimm_in,
    input  wire        is_ecall_in,
    input  wire        is_mret_in,
    input  wire        is_mul_in,
    input  wire        is_div_in,
    input  wire        is_bext_in,

    // 输出全部打一拍
    output reg  [31:0] e1_pc,
    output reg  [31:0] e1_pc4,
    output reg  [31:0] e1_instr,
    output reg  [31:0] e1_rs1,
    output reg  [31:0] e1_rs2,
    output reg  [31:0] e1_imm,
    output reg  [ 4:0] e1_rd_addr,
    output reg         e1_reg_we,
    output reg         e1_mem_we,
    output reg         e1_mem_re,
    output reg         e1_branch,
    output reg         e1_jump,
    output reg         e1_alu_src,
    output reg  [ 1:0] e1_wb_sel,
    output reg  [ 4:0] e1_alu_op,
    output reg  [ 1:0] e1_mem_width,
    output reg         e1_mem_sign,
    output reg         e1_predict_taken,   // 传预测结果到EX1
    output reg  [31:0] e1_predict_target,
    output reg  [ 1:0] e1_instr_type       // 传指令类型到EX1

    // Zicsr / Trap / M / B 扩展新增输出
    output reg         e1_is_csr,
    output reg  [ 1:0] e1_csr_op,
    output reg         e1_csr_uimm,
    output reg         e1_is_ecall,
    output reg         e1_is_mret,
    output reg         e1_is_mul,
    output reg         e1_is_div,
    output reg         e1_is_bext
);

  always @(posedge clk) begin
    if (rst || flush) begin
      e1_pc             <= 32'h0;
      e1_pc4            <= 32'h0;
      e1_instr          <= `INST_NOP;
      e1_rs1            <= 32'h0;
      e1_rs2            <= 32'h0;
      e1_imm            <= 32'h0;
      e1_rd_addr        <= 5'h0;
      e1_reg_we         <= 1'b0;
      e1_mem_we         <= 1'b0;
      e1_mem_re         <= 1'b0;
      e1_branch         <= 1'b0;
      e1_jump           <= 1'b0;
      e1_alu_src        <= 1'b0;
      e1_wb_sel         <= `WB_ALU;
      e1_alu_op         <= `ALU_ADD;
      e1_mem_width      <= `MEM_WORD;
      e1_mem_sign       <= 1'b1;
      e1_predict_taken  <= 1'b0;
      e1_predict_target <= 32'd0;
      e1_instr_type     <= 2'b00;  // 默认非分支指令

      // 扩展信号复位
      e1_is_csr         <= 1'b0;
      e1_csr_op         <= `CSR_OP_NONE;
      e1_csr_uimm       <= 1'b0;
      e1_is_ecall       <= 1'b0;
      e1_is_mret        <= 1'b0;
      e1_is_mul         <= 1'b0;
      e1_is_div         <= 1'b0;
      e1_is_bext        <= 1'b0;

    end else
    if (stall) begin
    end else begin
      e1_pc             <= pc_in;
      e1_pc4            <= pc4_in;
      e1_instr          <= instr_in;
      e1_rs1            <= rs1_in;
      e1_rs2            <= rs2_in;
      e1_imm            <= imm_in;
      e1_rd_addr        <= rd_addr_in;
      e1_reg_we         <= reg_we_in;
      e1_mem_we         <= mem_we_in;
      e1_mem_re         <= mem_re_in;
      e1_branch         <= branch_in;
      e1_jump           <= jump_in;
      e1_alu_src        <= alu_src_in;
      e1_wb_sel         <= wb_sel_in;
      e1_alu_op         <= alu_op_in;
      e1_mem_width      <= mem_width_in;
      e1_mem_sign       <= mem_sign_in;
      e1_predict_taken  <= predict_taken_in;
      e1_predict_target <= predict_target_in;
      e1_instr_type     <= instr_type_in;
      //扩展信号打拍
      e1_is_csr         <= is_csr_in;
      e1_csr_op         <= csr_op_in;
      e1_csr_uimm       <= csr_uimm_in;
      e1_is_ecall       <= is_ecall_in;
      e1_is_mret        <= is_mret_in;
      e1_is_mul         <= is_mul_in;
      e1_is_div         <= is_div_in;
      e1_is_bext        <= is_bext_in;
    end
  end

endmodule
