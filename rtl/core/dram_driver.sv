`timescale 1ns / 1ps

module dram_driver (
    input  logic         clk,
    input  logic [17:0]  perip_addr,
    input  logic [31:0]  perip_wdata,
    input  logic [1:0]   perip_mask,
    input  logic         dram_wen,
    output logic [31:0]  perip_rdata
);

    logic [15:0] dram_addr;
    logic [ 1:0] offset;
    logic [31:0] dram_rdata_raw;
    logic [31:0] dram_wdata_aligned;
    logic [ 3:0] wea;                   // 字节写使能

    assign dram_addr = perip_addr[17:2];
    assign offset    = perip_addr[1:0];

    // 字节写使能 + 数据对齐：SB/SH需要把数据移位到对应字节位置
    assign wea = dram_wen ? (
        (perip_mask == 2'b00) ? (4'b0001 << offset) :                     // SB：写1字节
        (perip_mask == 2'b01) ? (4'b0011 << {offset[1], 1'b0}) :          // SH：写2字节
        4'b1111                                                           // SW：写4字节
    ) : 4'b0000;

    // SB: 把最低字节复制到全部4个位置，BRAM按wea选取
    // SH: 把低16位复制到高16位
    assign dram_wdata_aligned = (perip_mask == 2'b00) ? {4{perip_wdata[7:0]}} :
                                (perip_mask == 2'b01) ? {2{perip_wdata[15:0]}} :
                                perip_wdata;

    bram_dram Mem_DRAM (
        .clka  (clk),
        .ena   (1'b1),
        .addra (dram_addr),
        .dina  (dram_wdata_aligned),
        .douta (dram_rdata_raw),
        .wea   (wea)
    );

    // 读数据对齐（IP核Latency=2，已内部打拍，此处不需额外寄存器）
    always_comb begin
        perip_rdata = 32'd0;
        case (perip_mask)
            2'b00: begin
                case (offset)
                    2'b00:  perip_rdata = {24'b0, dram_rdata_raw[7:0]};
                    2'b01:  perip_rdata = {24'b0, dram_rdata_raw[15:8]};
                    2'b10:  perip_rdata = {24'b0, dram_rdata_raw[23:16]};
                    2'b11:  perip_rdata = {24'b0, dram_rdata_raw[31:24]};
                endcase
            end
            2'b01: begin
                case (offset[1])
                    1'b0:   perip_rdata = {24'b0, dram_rdata_raw[15:0]};
                    1'b1:   perip_rdata = {24'b0, dram_rdata_raw[31:16]};
                endcase
            end
            2'b10: perip_rdata = dram_rdata_raw;
            default: perip_rdata = 32'd0;
        endcase
    end

endmodule
