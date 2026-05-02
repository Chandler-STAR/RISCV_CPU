`include "../include/defines.vh"

// MEM2→WB 流水线寄存器
module mem2_wb_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,          // DRAM停顿时保持
    input  wire [31:0] pc4_in,
    input  wire [31:0] instr_in,
    input  wire [31:0] alu_out_in,
    input  wire [31:0] mem_rdata_in,
    input  wire [ 4:0] rd_addr_in,
    input  wire        reg_we_in,
    input  wire [ 1:0] wb_sel_in,

    output reg  [31:0] w_pc4,
    output reg  [31:0] w_instr,
    output reg  [31:0] w_alu_out,
    output reg  [31:0] w_mem_rdata,
    output reg  [ 4:0] w_rd_addr,
    output reg         w_reg_we,
    output reg  [ 1:0] w_wb_sel
);

    always @(posedge clk) begin
        if (rst) begin
            w_pc4       <= 32'h0;
            w_instr     <= `INST_NOP;
            w_alu_out   <= 32'h0;
            w_mem_rdata <= 32'h0;
            w_rd_addr   <= 5'h0;
            w_reg_we    <= 1'b0;
            w_wb_sel    <= `WB_ALU;
        end else if (!stall) begin     // DRAM停顿时保持
            w_pc4       <= pc4_in;
            w_instr     <= instr_in;
            w_alu_out   <= alu_out_in;
            w_mem_rdata <= mem_rdata_in;
            w_rd_addr   <= rd_addr_in;
            w_reg_we    <= reg_we_in;
            w_wb_sel    <= wb_sel_in;
        end
    end

endmodule
