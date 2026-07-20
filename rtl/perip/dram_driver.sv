`timescale 1ns / 1ps
//简单双口寄存器BRAM: A口只写、B口只读
module dram_driver (
    input  logic         clk,
    input  logic [17:0]  perip_addr,
    input  logic [17:0]  perip_raddr,   // 读口独立地址(提前读时为 EX2 的 load 地址)
    input  logic [31:0]  perip_wdata,   // 写口数据
    input  logic [1:0]   perip_mask,
    input  logic         dram_wen,
    output logic [31:0]  perip_rdata,   // 读桥选择后的数据
    output logic [31:0]  perip_rdram    // 读口原始数据(不经字节提取/桥选择,供提前读捕获)
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

    //  简单双口 BRAM:A口只写、B口只读。读口不带字节写回选择逻辑,load 数据
    //   返回路径更短。读写地址分离:写口恒为 MEM1 地址(无选择逻辑),读口走 perip_raddr(提前读)。
    //   读写同址同拍=READ_FIRST(读到旧值)，CPU 侧 st_conflict 护栏保证该情形不发生提前读。
    bram_dram Mem_DRAM (
        .clka  (clk),
        .ena   (1'b1),
        .wea   (wea),
        .addra (dram_addr),               // A 口：写地址(恒 MEM1)
        .dina  (dram_wdata_aligned),
        .clkb  (clk),
        .enb   (1'b1),
        .addrb (perip_raddr[17:2]),       // B 口：读地址(独立,early 时为 EX2 load 地址)
        .doutb (dram_rdata_raw)           // B 口：读数据(latency-1, 干净无写回 mux)
    );

    assign perip_rdram = dram_rdata_raw;   // 原始读数据导出,供核内直接捕获

    // 读数据对齐（B 口 latency-1，已内部打拍）
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
