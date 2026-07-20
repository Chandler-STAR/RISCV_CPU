`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/16/2025 06:21:13 PM
// Design Name: 
// Module Name: student_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module student_top#(
    parameter                           P_SW_CNT            = 64,
    parameter                           P_LED_CNT           = 32,
    parameter                           P_SEG_CNT           = 40,
    parameter                           P_KEY_CNT           = 8
) (
    input                                       w_cpu_clk     ,
    input                                       w_clk_50Mhz   ,
    input                                       w_clk_rst     ,
    input  [P_KEY_CNT - 1:0]                    virtual_key   ,
    input  [P_SW_CNT  - 1:0]                    virtual_sw    ,

    output [P_LED_CNT - 1:0]                    virtual_led   ,
    output [P_SEG_CNT - 1:0]                    virtual_seg   
);

    // IROM双发取指:A 口=pc,B 口=pc+4
    // irom_bram IP,例化了两份
    logic [31:0] pc, pc2;
    logic [11:0] inst_addr, inst_addr2;
    logic [31:0] instruction, instruction2;

    // perip
    logic [31:0] perip_addr, perip_raddr, perip_wdata, perip_rdata, perip_rdram;
    logic perip_wen;
    logic [1:0] perip_mask;

    // 16KB IROM 即  2^12 * 32bit，14位 地址空间，按 4byte 对齐
    assign inst_addr  = pc[13:2];
    assign inst_addr2 = pc2[13:2];

    myCPU Core_cpu (
        .cpu_rst            (w_clk_rst),
        .cpu_clk            (w_cpu_clk),

        // Interface to IROM
        .irom_addr          (pc),               //IROM 
        .irom_data          (instruction),   
        .irom_addr2         (pc2),    
        .irom_data2         (instruction2),     //IROM B

        // Interface to DRAM & periphera
        .perip_addr         (perip_addr),
        .perip_raddr        (perip_raddr),
        .perip_wen          (perip_wen),
        .perip_mask         (perip_mask),   
        .perip_wdata        (perip_wdata),
        .perip_rdata        (perip_rdata),
        .perip_rdram        (perip_rdram)
    );

    // 注意指令存储器更换为BRAM，为同步读需等一拍
    irom_bram Mem_IROM (
        .clka       (w_cpu_clk),
        .addra      (inst_addr),
        .douta      (instruction)
    );

    irom_bram Mem_IROM_B (
        .clka       (w_cpu_clk),
        .addra      (inst_addr2),
        .douta      (instruction2)
    );
    
    //数据存储器更改为简单双口，vivado里面Simple Dual Port A口只写，B口只读
    perip_bridge bridge_inst (
        .clk				(w_cpu_clk),
        .cnt_clk            (w_clk_50Mhz),
        .rst                (w_clk_rst),
        .perip_addr			(perip_addr),   //B口只读，读地址
        .perip_raddr		(perip_raddr),  //A口只写，写地址
        .perip_wdata		(perip_wdata),  //A口写数据
        .perip_wen			(perip_wen),    
        .perip_mask			(perip_mask),
        .perip_rdata		(perip_rdata),  //B口只读，选路后的读数据
        .perip_rdram		(perip_rdram),  //B口只读，原始数据数据
        .virtual_sw_input	(virtual_sw),
        .virtual_key_input	(virtual_key),	
        .virtual_seg_output	(virtual_seg),
        .virtual_led_output (virtual_led)
    );

endmodule
