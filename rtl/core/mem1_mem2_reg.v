// MEM1→MEM2 流水线寄存器
module mem1_mem2_reg (
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

    output reg  [31:0] m2_pc4,
    output reg  [31:0] m2_instr,
    output reg  [31:0] m2_alu_out,
    output reg  [31:0] m2_mem_rdata,
    output reg  [ 4:0] m2_rd_addr,
    output reg         m2_reg_we,
    output reg  [ 1:0] m2_wb_sel
);

    always @(posedge clk) begin
        if (rst) begin
            m2_pc4       <= 32'h0;
            m2_instr     <= 32'h00000013;
            m2_alu_out   <= 32'h0;
            m2_mem_rdata <= 32'h0;
            m2_rd_addr   <= 5'h0;
            m2_reg_we    <= 1'b0;
            m2_wb_sel    <= 2'd0;
        end else if (!stall) begin     // DRAM停顿时保持，等待BRAM数据
            m2_pc4       <= pc4_in;
            m2_instr     <= instr_in;
            m2_alu_out   <= alu_out_in;
            m2_mem_rdata <= mem_rdata_in;
            m2_rd_addr   <= rd_addr_in;
            m2_reg_we    <= reg_we_in;
            m2_wb_sel    <= wb_sel_in;
        end
    end

endmodule
