`include "../include/defines.vh"
//`include "defines.vh"

module ex_mem_reg (
    input clk,
    input rst,
    //input
    input [31:0] pc4_in,
    input [31:0] instr_in,
    input [31:0] alu_out_in,
    input [31:0] rs2_in,
    input [4:0] rd_addr_in,
    input reg_we_in,
    input mem_we_in,
    input mem_re_in,
    input [1:0] wb_sel_in,
    input [1:0] mem_width_in,
    input mem_sign_in,
    //output
    output reg [31:0] m_pc4,
    output reg [31:0] m_instr,
    output reg [31:0] m_alu_out,
    output reg [31:0] m_rs2,
    output reg [4:0] m_rd_addr,
    output reg m_reg_we,
    output reg m_mem_we,
    output reg m_mem_re,
    output reg [1:0] m_wb_sel,
    output reg [1:0] m_mem_width,
    output reg m_mem_sign
);

  always @(posedge clk) begin
    if (rst) begin
      //此处初始化需后期检查，确保与设计需求一致
      m_pc4 <= 32'h0;
      m_instr <= `INST_NOP;
      m_alu_out <= 32'h0;
      m_rs2 <= 32'h0;
      m_rd_addr <= 5'h0;
      m_reg_we <= 1'b0;
      m_mem_we <= 1'b0;
      m_mem_re <= 1'b0;
      m_wb_sel <= 2'b00;
      m_mem_width <= 2'b00;
      m_mem_sign <= 1'b1;  // 默认有符号扩展
    end else begin
      m_pc4 <= pc4_in;
      m_instr <= instr_in;
      m_alu_out <= alu_out_in;
      m_rs2 <= rs2_in;
      m_rd_addr <= rd_addr_in;
      m_reg_we <= reg_we_in;
      m_mem_we <= mem_we_in;
      m_mem_re <= mem_re_in;
      m_wb_sel <= wb_sel_in;
      m_mem_width <= mem_width_in;
      m_mem_sign <= mem_sign_in;
    end
  end




endmodule  //ex_mem_reg
