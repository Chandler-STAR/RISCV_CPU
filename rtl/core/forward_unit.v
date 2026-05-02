`include "../include/defines.vh"

// 数据转发单元 —— 7级流水线
// 检测后续阶段的目的寄存器是否与EX1的源寄存器匹配
// 匹配时产生转发控制信号，在EX1的ALU输入多选器中选择转发数据
// 关键：Load指令在EX2/MEM1阶段不转发（此时只有地址，无数据）
//        Load数据在MEM2阶段（m2_mem_rdata）或WB阶段（wb_data）才可转发
module forward_unit (
    // EX1阶段——消费者（需要转发数据的阶段）
    input  wire [ 4:0] e1_rs1_addr,     // EX1的rs1地址
    input  wire [ 4:0] e1_rs2_addr,     // EX1的rs2地址
    input  wire        e1_rs1_en,       // rs1是否真实使用
    input  wire        e1_rs2_en,       // rs2是否真实使用

    // EX2阶段——领先1拍（ALU结果有效，Load数据无效）
    input  wire [ 4:0] e2_rd_addr,      // EX2的rd地址
    input  wire        e2_reg_we,       // EX2的写使能
    input  wire [ 1:0] e2_wb_sel,       // EX2的写回来源（WB_MEM=Load则禁止转发）

    // MEM1阶段——领先2拍
    input  wire [ 4:0] m1_rd_addr,
    input  wire        m1_reg_we,
    input  wire [ 1:0] m1_wb_sel,

    // MEM2阶段——领先3拍（Load数据在此阶段可用）
    input  wire [ 4:0] m2_rd_addr,
    input  wire        m2_reg_we,
    input  wire [ 1:0] m2_wb_sel,       // WB_ALU用m2_alu_out，WB_MEM用m2_mem_rdata

    // WB阶段——领先4拍
    input  wire [ 4:0] w_rd_addr,
    input  wire        w_reg_we,

    // 转发控制输出（3bit，5选1）
    output reg  [ 2:0] fwd_a,           // ALU A口转发选择
    output reg  [ 2:0] fwd_b            // ALU B口转发选择
);

    // 各阶段转发有效性：
    // EX2/MEM1只能转发ALU结果（wb_sel != WB_MEM），Load的数据还没出来
    wire e2_valid = e2_reg_we && (e2_wb_sel != `WB_MEM);   // Load在EX2不转发
    wire m1_valid = m1_reg_we && (m1_wb_sel != `WB_MEM);   // Load在MEM1不转发
    wire m2_valid = m2_reg_we;           // MEM2的Load/ALU数据都有效
    wire w_valid  = w_reg_we;            // WB数据始终有效

    // ALU A口转发：越近的优先级越高
    always @(*) begin
        if (e1_rs1_en && e2_valid && (e2_rd_addr != 5'd0) && (e2_rd_addr == e1_rs1_addr))
            fwd_a = `FWD_EX2;
        else if (e1_rs1_en && m1_valid && (m1_rd_addr != 5'd0) && (m1_rd_addr == e1_rs1_addr))
            fwd_a = `FWD_MEM1;
        else if (e1_rs1_en && m2_valid && (m2_rd_addr != 5'd0) && (m2_rd_addr == e1_rs1_addr))
            fwd_a = `FWD_MEM2;
        else if (e1_rs1_en && w_valid && (w_rd_addr != 5'd0) && (w_rd_addr == e1_rs1_addr))
            fwd_a = `FWD_WB;
        else
            fwd_a = `FWD_NONE;
    end

    // ALU B口转发：仅当rs2真实使用时才检测匹配
    always @(*) begin
        if (e1_rs2_en && e2_valid && (e2_rd_addr != 5'd0) && (e2_rd_addr == e1_rs2_addr))
            fwd_b = `FWD_EX2;
        else if (e1_rs2_en && m1_valid && (m1_rd_addr != 5'd0) && (m1_rd_addr == e1_rs2_addr))
            fwd_b = `FWD_MEM1;
        else if (e1_rs2_en && m2_valid && (m2_rd_addr != 5'd0) && (m2_rd_addr == e1_rs2_addr))
            fwd_b = `FWD_MEM2;
        else if (e1_rs2_en && w_valid && (w_rd_addr != 5'd0) && (w_rd_addr == e1_rs2_addr))
            fwd_b = `FWD_WB;
        else
            fwd_b = `FWD_NONE;
    end

endmodule
