/* `include "../include/defines.vh"
module id_ex_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush_id_ex,
    // ── 数据输入 ─────────────────────────────
    input  wire [31:0] pc_in,
    input  wire [31:0] pc4_in,
    input  wire [31:0] instr_in,
    input  wire [31:0] rs1_in,
    input  wire [31:0] rs2_in,
    input  wire [31:0] imm_in,
    input  wire [ 4:0] rd_addr_in,
    input  wire        branch_taken_in,
    // ── 控制信号输入 ─────────────────────────
    input  wire        reg_we_in,
    input  wire        mem_we_in,
    input  wire        mem_re_in,
    input  wire        branch_in,
    input  wire        jump_in,
    input  wire        alu_src_in,
    input  wire [ 1:0] wb_sel_in,
    input  wire [ 3:0] alu_op_in,
    input  wire [ 1:0] mem_width_in,
    input  wire        mem_sign_in,
    // ── 数据输出 ─────────────────────────────
    output reg  [31:0] e_pc,
    output reg  [31:0] e_pc4,
    output reg  [31:0] e_instr,
    output reg  [31:0] e_rs1,
    output reg  [31:0] e_rs2,
    output reg  [31:0] e_imm,
    output reg  [ 4:0] e_rd_addr,
    output reg         e_branch_taken,
    // ── 控制信号输出 ─────────────────────────
    output reg         e_reg_we,
    output reg         e_mem_we,
    output reg         e_mem_re,
    output reg         e_branch,
    output reg         e_jump,
    output reg         e_alu_src,
    output reg  [ 1:0] e_wb_sel,
    output reg  [ 3:0] e_alu_op,
    output reg  [ 1:0] e_mem_width,
    output reg         e_mem_sign
);
  always @(posedge clk) begin
    if (rst || flush_id_ex) begin  // 复位或清空时，所有输出恢复到默认值
      e_pc           <= 32'h0;
      e_pc4          <= 32'h0;
      e_instr        <= `INST_NOP;  // NOP
      e_rs1          <= 32'h0;
      e_rs2          <= 32'h0;
      e_imm          <= 32'h0;
      e_rd_addr      <= 5'h0;
      e_branch_taken <= 1'b0;
      e_reg_we       <= 1'b0;
      e_mem_we       <= 1'b0;
      e_mem_re       <= 1'b0;
      e_branch       <= 1'b0;
      e_jump         <= 1'b0;
      e_alu_src      <= 1'b0;
      e_wb_sel       <= `WB_ALU;
      e_alu_op       <= `ALU_ADD;
      e_mem_width    <= `MEM_WORD;
      e_mem_sign     <= 1'b1;
    end else begin  // 正常传递
      e_pc           <= pc_in;
      e_pc4          <= pc4_in;
      e_instr        <= instr_in;
      e_rs1          <= rs1_in;
      e_rs2          <= rs2_in;
      e_imm          <= imm_in;
      e_rd_addr      <= rd_addr_in;
      e_branch_taken <= branch_taken_in;
      e_reg_we       <= reg_we_in;
      e_mem_we       <= mem_we_in;
      e_mem_re       <= mem_re_in;
      e_branch       <= branch_in;
      e_jump         <= jump_in;
      e_alu_src      <= alu_src_in;
      e_wb_sel       <= wb_sel_in;
      e_alu_op       <= alu_op_in;
      e_mem_width    <= mem_width_in;
      e_mem_sign     <= mem_sign_in;
    end
  end
endmodule
 */

`include "../include/defines.vh"

module id_ex_reg (
    input wire        clk,
    input wire        rst,
    input wire        flush_id_ex,
    // ── 数据输入 ─────────────────────────────
    input wire [31:0] pc_in,
    input wire [31:0] pc4_in,
    input wire [31:0] instr_in,
    input wire [31:0] rs1_in,
    input wire [31:0] rs2_in,
    input wire [31:0] imm_in,
    input wire [ 4:0] rd_addr_in,
    // branch_taken_in 已删除，因为比较逻辑移到了 EX 段

    // ── 控制信号输入 ─────────────────────────
    input wire        reg_we_in,
    input wire        mem_we_in,
    input wire        mem_re_in,
    input wire        branch_in,
    input wire        jump_in,
    input wire        alu_src_in,
    input wire [ 1:0] wb_sel_in,
    input wire [ 3:0] alu_op_in,
    input wire [ 1:0] mem_width_in,
    input wire        mem_sign_in,
    input wire        predict_taken_in,  // 来自分支预测器的预测结果
    input wire [31:0] predict_target_in, // 来自分支预测器的预测目标地址

    // ── 数据输出 ─────────────────────────────
    output reg [31:0] e_pc,
    output reg [31:0] e_pc4,
    output reg [31:0] e_instr,
    output reg [31:0] e_rs1,
    output reg [31:0] e_rs2,
    output reg [31:0] e_imm,
    output reg [ 4:0] e_rd_addr,
    // e_branch_taken 已删除
    output reg        e_predict_taken,  // 传递预测结果到 EX 段
    output reg [31:0] e_predict_target, // 传递预测目标到 EX 段

    // ── 控制信号输出 ─────────────────────────
    output reg       e_reg_we,
    output reg       e_mem_we,
    output reg       e_mem_re,
    output reg       e_branch,
    output reg       e_jump,
    output reg       e_alu_src,
    output reg [1:0] e_wb_sel,
    output reg [3:0] e_alu_op,
    output reg [1:0] e_mem_width,
    output reg       e_mem_sign
);

  always @(posedge clk) begin
    if (rst || flush_id_ex) begin  // 复位或清空时，所有输出恢复到默认值
      e_pc             <= 32'h0;
      e_pc4            <= 32'h0;
      e_instr          <= `INST_NOP;  // 使用 NOP 指令清空
      e_rs1            <= 32'h0;
      e_rs2            <= 32'h0;
      e_imm            <= 32'h0;
      e_rd_addr        <= 5'h0;
      e_reg_we         <= 1'b0;
      e_mem_we         <= 1'b0;
      e_mem_re         <= 1'b0;
      e_branch         <= 1'b0;
      e_jump           <= 1'b0;
      e_alu_src        <= 1'b0;
      e_wb_sel         <= `WB_ALU;
      e_alu_op         <= `ALU_ADD;
      e_mem_width      <= `MEM_WORD;
      e_mem_sign       <= 1'b1;
      e_predict_taken  <= 1'b0;  // 预测结果默认不跳转
      e_predict_target <= 32'h0;  // 预测目标默认无效
    end else begin  // 正常传递
      e_pc             <= pc_in;
      e_pc4            <= pc4_in;
      e_instr          <= instr_in;
      e_rs1            <= rs1_in;
      e_rs2            <= rs2_in;
      e_imm            <= imm_in;
      e_rd_addr        <= rd_addr_in;
      e_reg_we         <= reg_we_in;
      e_mem_we         <= mem_we_in;
      e_mem_re         <= mem_re_in;
      e_branch         <= branch_in;
      e_jump           <= jump_in;
      e_alu_src        <= alu_src_in;
      e_wb_sel         <= wb_sel_in;
      e_alu_op         <= alu_op_in;
      e_mem_width      <= mem_width_in;
      e_mem_sign       <= mem_sign_in;
      e_predict_taken  <= predict_taken_in;  // 传递预测结果
      e_predict_target <= predict_target_in;  // 传递预测目标地址
    end
  end

endmodule
