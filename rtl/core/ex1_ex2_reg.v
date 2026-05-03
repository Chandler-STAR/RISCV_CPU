// EX1→EX2 流水线寄存器
module ex1_ex2_reg (
    input wire        clk,
    input wire        rst,
    input wire        flush,              // 分支跳转时冲刷错误路径指令
    input wire        stall,              // DRAM停顿时保持
    input wire [31:0] pc_in,
    input wire [31:0] pc4_in,
    input wire [31:0] instr_in,
    input wire [31:0] rs2_in,
    input wire [31:0] alu_out_in,
    input wire [31:0] pc_branch_in,
    input wire        branch_taken_in,
    input wire [ 4:0] rd_addr_in,
    input wire        reg_we_in,
    input wire        mem_we_in,
    input wire        mem_re_in,
    input wire        branch_in,
    input wire        jump_in,
    input wire        mem_sign_in,
    input wire [ 1:0] wb_sel_in,
    input wire [ 1:0] mem_width_in,
    input wire        predict_taken_in,
    input wire [31:0] predict_target_in,
    input wire [ 1:0] instr_type_in,

    output reg [31:0] e2_pc,
    output reg [31:0] e2_pc4,
    output reg [31:0] e2_instr,
    output reg [31:0] e2_rs2,
    output reg [31:0] e2_alu_out,
    output reg [31:0] e2_pc_branch,
    output reg        e2_branch_taken,
    output reg [ 4:0] e2_rd_addr,
    output reg        e2_reg_we,
    output reg        e2_mem_we,
    output reg        e2_mem_re,
    output reg        e2_branch,
    output reg        e2_jump,
    output reg        e2_mem_sign,
    output reg [ 1:0] e2_wb_sel,
    output reg [ 1:0] e2_mem_width,
    output reg        e2_predict_taken,
    output reg [31:0] e2_predict_target,
    output reg [ 1:0] e2_instr_type
);

  always @(posedge clk) begin
    if (rst) begin
      e2_pc             <= 32'h0;
      e2_pc4            <= 32'h0;
      e2_instr          <= 32'h00000013;
      e2_rs2            <= 32'h0;
      e2_alu_out        <= 32'h0;
      e2_pc_branch      <= 32'h0;
      e2_branch_taken   <= 1'b0;
      e2_rd_addr        <= 5'h0;
      e2_reg_we         <= 1'b0;
      e2_mem_we         <= 1'b0;
      e2_mem_re         <= 1'b0;
      e2_branch         <= 1'b0;
      e2_jump           <= 1'b0;
      e2_mem_sign       <= 1'b1;
      e2_wb_sel         <= 2'd0;
      e2_mem_width      <= 2'd0;
      e2_predict_taken  <= 1'b0;
      e2_predict_target <= 32'd0;
      e2_instr_type     <= 2'b00;
    end else
    if (stall) begin  // 停顿优先于冲刷
    end else if (flush) begin
      e2_pc             <= 32'h0;
      e2_pc4            <= 32'h0;
      e2_instr          <= 32'h00000013;
      e2_rs2            <= 32'h0;
      e2_alu_out        <= 32'h0;
      e2_pc_branch      <= 32'h0;
      e2_branch_taken   <= 1'b0;
      e2_rd_addr        <= 5'h0;
      e2_reg_we         <= 1'b0;
      e2_mem_we         <= 1'b0;
      e2_mem_re         <= 1'b0;
      e2_branch         <= 1'b0;
      e2_jump           <= 1'b0;
      e2_mem_sign       <= 1'b1;
      e2_wb_sel         <= 2'd0;
      e2_mem_width      <= 2'd0;
      e2_predict_taken  <= 1'b0;
      e2_predict_target <= 32'd0;
      e2_instr_type     <= 2'b00;
    end else begin
      e2_pc             <= pc_in;
      e2_pc4            <= pc4_in;
      e2_instr          <= instr_in;
      e2_rs2            <= rs2_in;
      e2_alu_out        <= alu_out_in;
      e2_pc_branch      <= pc_branch_in;
      e2_branch_taken   <= branch_taken_in;
      e2_rd_addr        <= rd_addr_in;
      e2_reg_we         <= reg_we_in;
      e2_mem_we         <= mem_we_in;
      e2_mem_re         <= mem_re_in;
      e2_branch         <= branch_in;
      e2_jump           <= jump_in;
      e2_mem_sign       <= mem_sign_in;
      e2_wb_sel         <= wb_sel_in;
      e2_mem_width      <= mem_width_in;
      e2_predict_taken  <= predict_taken_in;
      e2_predict_target <= predict_target_in;
      e2_instr_type     <= instr_type_in;
    end
  end

endmodule
