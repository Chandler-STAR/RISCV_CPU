`include "../include/defines.vh"

module mem_wb_reg (
    //input
    input        clk,
    input        rst,
    input [31:0] pc4_in,        //← m_pc4
    input [31:0] instr_in,      //← m_instr（forward_unit.instr_wb 用）
    input [31:0] alu_out_in,    //← m_alu_out
    input [31:0] rs2_in,        //← dmem.mem_rdata
    input [31:0] mem_data_in,   //← m_rd_addr
    input [4:0]  rd_addr_in,    //← m_rd_addr
    input        reg_we_in,     //← m_reg_we
    input [1:0]  wb_sel_in,     //← m_wb_sel 

    //output
    output reg [31:0] w_pc4,
    output reg [31:0] w_instr,
    output reg [31:0] w_alu_out,
    output reg [31:0] w_mem_rdata,
    output reg [4:0]  w_rd_addr,
    output reg        w_reg_we,
    output reg [1:0]  w_wb_sel
);


always @(posedge clk) begin
    if (rst) begin  
        w_pc4       <= 32'b0;
        w_instr     <= `INST_NOP;
        w_alu_out   <= 32'b0;
        w_mem_rdata <= 32'b0;
        w_rd_addr   <= 5'b0;
        w_reg_we    <= 1'b0;
        w_wb_sel    <= 2'b0;    //这个初始值我还不确定
    end else begin
        w_pc4       <= pc4_in;
        w_instr     <= instr_in;
        w_alu_out   <= alu_out_in;
        w_mem_rdata <= mem_data_in;
        w_rd_addr   <= rd_addr_in;
        w_reg_we    <= reg_we_in;
        w_wb_sel    <= wb_sel_in;
    end
end
endmodule