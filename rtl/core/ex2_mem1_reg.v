`include "../include/defines.vh"
// EX2→MEM1 流水线寄存器
// 无flush:分支在 EX2 已解析并提交,进 MEM1 的都是对的指令

module ex2_mem1_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,          // DRAM停顿时保持
    input  wire [31:0] pc4_in,
    input  wire [31:0] instr_in,
    input  wire [31:0] alu_out_in,
    input  wire [31:0] rs2_in,        // store要写的数据
    input  wire [ 4:0] rd_addr_in,
    input  wire        reg_we_in,
    input  wire        mem_we_in,
    input  wire        mem_re_in,
    input  wire        mem_sign_in,
    input  wire [ 1:0] wb_sel_in,
    input  wire [ 1:0] mem_width_in,
    input  wire        fused_in,          // 宏操作融合:熔合对标志
    input  wire        valid_in,          // 这一格装的是真指令,不是流水线气泡

    output reg  [31:0] m1_pc4,
    output reg  [31:0] m1_instr,
    output reg  [31:0] m1_alu_out,
    output reg  [31:0] m1_rs2,
    output reg  [ 4:0] m1_rd_addr,
    output reg         m1_reg_we,
    output reg         m1_mem_we,
    output reg         m1_mem_re,
    output reg         m1_mem_sign,
    output reg  [ 1:0] m1_wb_sel,
    output reg  [ 1:0] m1_mem_width,
    output reg         m1_fused,
    output reg         m1_valid
);

    always @(posedge clk) begin
        if (rst) begin
            m1_pc4       <= 32'h0;
            m1_instr     <= `INST_NOP;
            m1_alu_out   <= 32'h0;
            m1_rs2       <= 32'h0;
            m1_rd_addr   <= 5'h0;
            m1_reg_we    <= 1'b0;
            m1_mem_we    <= 1'b0;
            m1_mem_re    <= 1'b0;
            m1_mem_sign  <= 1'b1;
            m1_wb_sel    <= 2'd0;
            m1_mem_width <= 2'd0;
            m1_fused     <= 1'b0;
            m1_valid     <= 1'b0;
        end else if (!stall) begin     // DRAM停顿时保持，让BRAM数据赶到
            m1_pc4       <= pc4_in;
            m1_instr     <= instr_in;
            m1_alu_out   <= alu_out_in;
            m1_rs2       <= rs2_in;
            m1_rd_addr   <= rd_addr_in;
            m1_reg_we    <= reg_we_in;
            m1_mem_we    <= mem_we_in;
            m1_mem_re    <= mem_re_in;
            m1_mem_sign  <= mem_sign_in;
            m1_wb_sel    <= wb_sel_in;
            m1_mem_width <= mem_width_in;
            m1_fused     <= fused_in;
            m1_valid     <= valid_in;
        end
    end

endmodule
