`include "../include/defines.vh"

// 数据转发单元
// 检测后续阶段的目的寄存器是否与 EX1 的源寄存器匹配,
// 匹配时产生转发编码,供 EX1 的 ALU 输入多选器选择转发数据。
// Load 指令在 EX2/MEM1 阶段通常还没有数据,不参与转发;例外是快速路径已拿到
// 数据的场合(e2_load_ok / m1_load_ok 置位)。其余 load 要到 WB(w_mem_rdata)才可转发。
module forward_unit (
    // EX1阶段——后续指令（需要转发数据的阶段）
    input  wire [ 4:0] e1_rs1_addr,     // EX1的rs1地址
    input  wire [ 4:0] e1_rs2_addr,     // EX1的rs2地址
    input  wire        e1_rs1_en,       // rs1是否真实使用
    input  wire        e1_rs2_en,       // rs2是否真实使用

    // EX2阶段——领先1拍(ALU结果有效;Load 仅在 EX1 提前查表命中时才有数据）
    input  wire [ 4:0] e2_rd_addr,      // EX2的rd地址
    input  wire        e2_reg_we,       // EX2的写使能
    input  wire [ 1:0] e2_wb_sel,       // EX2的写回来源（WB_MEM=Load则禁止转发）
    input  wire        e2_is_pmul,      // 流水化乘法在 EX2(结果未好,禁转发)
    input  wire        e2_load_ok,      // EX2的load已经提前拿到数据(缓冲命中),可以转发

    // MEM1阶段——领先2拍
    input  wire [ 4:0] m1_rd_addr,
    input  wire        m1_reg_we,
    input  wire [ 1:0] m1_wb_sel,
    input  wire        m1_load_ok,      // 该 load 在 MEM1 有可转发数据(缓冲命中/直传/投机读,三者之一)
    input  wire        m1_is_pmul,      // 流水化乘法在 MEM1(结果本级末才好,禁转发;下拍走 WB )

    // WB阶段——领先3拍（Load数据在此阶段可用）
    input  wire [ 4:0] w_rd_addr,
    input  wire        w_reg_we,
    input  wire [ 1:0] w_wb_sel,       // WB_ALU 取 w_alu_out;WB_MEM 取 w_mem_rdata

    // 转发控制输出（3bit编码，8种转发来源之一）
    output reg  [ 2:0] fwd_a,           // ALU A口转发选择
    output reg  [ 2:0] fwd_b            // ALU B口转发选择
);

    // 各阶段转发有效性：
    // EX2/MEM1一般只转发ALU/链接结果（wb_sel != WB_MEM）；
    // Load数据通常尚未返回，只有提前命中（load_ok）时才允许转发
    wire e2_valid = e2_reg_we && (e2_wb_sel != `WB_MEM || e2_load_ok) && !e2_is_pmul;   // Load在EX2一般不转发,提前读已命中时例外;流水化乘法结果未好,不转发
    wire m1_valid = m1_reg_we && (m1_wb_sel != `WB_MEM || m1_load_ok) && !m1_is_pmul;   // Load在MEM1一般不转发,store-buffer命中时例外;流水化乘法结果未好,不转发
    wire w_valid = w_reg_we;           // WB的Load/ALU数据都有效

    // 按(阶段,写回来源)直接给出 8 选 1 编码——子选择并入编码域,数据腿全部寄存器直连
    // load 提前命中时同样发复用腿编码(腿内由"是否 load"判别取链接值还是 load 数据)
    wire [2:0] e2_code = (e2_wb_sel == `WB_PC4 || e2_wb_sel == `WB_MEM) ? `FWD_EX2P : `FWD_EX2;
    wire [2:0] w_code = (w_wb_sel == `WB_MEM) ? `FWD_WB_MEM :
                         (w_wb_sel == `WB_PC4) ? `FWD_WB_PC4   : `FWD_WB_ALU;

    // ALU A口转发：越近的优先级越高
    always @(*) begin
        if (e1_rs1_en && e2_valid && (e2_rd_addr != 5'd0) && (e2_rd_addr == e1_rs1_addr))
            fwd_a = e2_code;
        else if (e1_rs1_en && m1_valid && (m1_rd_addr != 5'd0) && (m1_rd_addr == e1_rs1_addr))
            fwd_a = `FWD_MEM1;
        else if (e1_rs1_en && w_valid && (w_rd_addr != 5'd0) && (w_rd_addr == e1_rs1_addr))
            fwd_a = w_code;
        else
            fwd_a = `FWD_NONE;
    end

    // ALU B口转发：仅当rs2真实使用时才检测匹配
    always @(*) begin
        if (e1_rs2_en && e2_valid && (e2_rd_addr != 5'd0) && (e2_rd_addr == e1_rs2_addr))
            fwd_b = e2_code;
        else if (e1_rs2_en && m1_valid && (m1_rd_addr != 5'd0) && (m1_rd_addr == e1_rs2_addr))
            fwd_b = `FWD_MEM1;
        else if (e1_rs2_en && w_valid && (w_rd_addr != 5'd0) && (w_rd_addr == e1_rs2_addr))
            fwd_b = w_code;
        else
            fwd_b = `FWD_NONE;
    end

endmodule
