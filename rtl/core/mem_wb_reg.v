`include "../include/defines.vh"
// MEM1→WB 流水线寄存器:访存级和写回级之间的一排触发器
// (原来这里有 mem1_mem2_reg 和 mem2_wb_reg 两排,后一排是多余的,已合成一排)
module mem_wb_reg (
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
    input  wire        fused_in,       // 宏操作融合(macro-op fusion)标志:本条由两条指令熔成,指令计数按 2 条算
    input  wire        valid_in,       // 本条是真指令;流水线停顿时插入的空指令(气泡)此位为 0

    output reg  [31:0] w_pc4,
    output reg  [31:0] w_instr,
    output reg  [31:0] w_alu_out,
    output reg  [31:0] w_mem_rdata,
    output reg  [ 4:0] w_rd_addr,
    output reg         w_reg_we,
    output reg  [ 1:0] w_wb_sel,
    output reg         w_fused,       // 同 fused_in,随流水传到写回:指令计数 +2 在这一级发生
    output reg         w_valid        // 给指令计数器 minstret 用:只有真指令写回才 +1,气泡不算
);

    always @(posedge clk) begin
        if (rst) begin
            w_pc4       <= 32'h0;
            w_instr     <= `INST_NOP;
            w_alu_out   <= 32'h0;
            w_mem_rdata <= 32'h0;
            w_rd_addr   <= 5'h0;
            w_reg_we    <= 1'b0;
            w_wb_sel    <= 2'd0;
            w_fused     <= 1'b0;
            w_valid     <= 1'b0;
        end else if (!stall) begin     // DRAM停顿时保持，等待BRAM数据
            w_pc4       <= pc4_in;
            w_instr     <= instr_in;
            w_alu_out   <= alu_out_in;
            w_mem_rdata <= mem_rdata_in;
            w_rd_addr   <= rd_addr_in;
            w_reg_we    <= reg_we_in;
            w_wb_sel    <= wb_sel_in;
            w_fused     <= fused_in;
            w_valid     <= valid_in;
        end
    end

endmodule
