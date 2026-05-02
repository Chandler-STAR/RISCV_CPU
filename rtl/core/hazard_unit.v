`include "../include/defines.vh"
// 检测两类冲突：
//   1. Load-Use 冲突：load指令与ID阶段指令的源寄存器重叠
//      → 停顿IF/ID，冲刷ID/EX1插入气泡，直到load到达MEM2可转发
//   2. 分支/跳转：EX2阶段解析跳转 → 冲刷IF/ID和ID/EX1的两条错误路径指令
module hazard_unit (
    // ID阶段——消费者（被检测是否依赖in-flight load）
    input  wire [ 4:0] rs1_id,          // ID阶段rs1地址
    input  wire [ 4:0] rs2_id,          // ID阶段rs2地址
    input  wire        rs1_en,          // ID指令是否真正使用rs1
    input  wire        rs2_en,          // ID指令是否真正使用rs2

    // EX1阶段——load在此阶段，数据3拍后到MEM2
    input  wire [ 4:0] e1_rd_addr,
    input  wire        e1_mem_re,       // EX1是否为load指令

    // EX2阶段——load在此阶段，数据2拍后到MEM2
    input  wire [ 4:0] e2_rd_addr,
    input  wire        e2_mem_re,

    // MEM1阶段——load在此阶段，dram_driver寄存器使数据延迟1拍
    input  wire [ 4:0] m1_rd_addr,
    input  wire        m1_mem_re,
    input  wire        dram_stall,      // DRAM停顿时数据未到MEM2，仍需暂停

    // EX2阶段PC控制——分支/跳转在此阶段解析
    input  wire        e2_pc_sel,       // 分支条件满足 或 无条件跳转
    output wire        stall,           // 停顿IF/ID（冻结PC和IF/ID寄存器）
    output wire        flush_if_id,     // 冲刷IF/ID（分支跳转时清除紧跟的指令）
    output wire        flush_id_ex1     // 冲刷ID/EX1（插入气泡 或 清除第二条错误指令）
);

    // Load-Use：仅检查rs1和真正使用rs2的指令
    wire rs1_match_ex1  = rs1_en && e1_mem_re && (e1_rd_addr != 5'd0) && (e1_rd_addr == rs1_id);
    wire rs2_match_ex1  = rs2_en && e1_mem_re && (e1_rd_addr != 5'd0) && (e1_rd_addr == rs2_id);
    wire load_use_ex1   = rs1_match_ex1 || rs2_match_ex1;

    wire rs1_match_ex2  = rs1_en && e2_mem_re && (e2_rd_addr != 5'd0) && (e2_rd_addr == rs1_id);
    wire rs2_match_ex2  = rs2_en && e2_mem_re && (e2_rd_addr != 5'd0) && (e2_rd_addr == rs2_id);
    wire load_use_ex2   = rs1_match_ex2 || rs2_match_ex2;

    // Latency=2: load在MEM1且stall活跃时数据未到MEM2，仍需停顿
    wire rs1_match_m1  = rs1_en && m1_mem_re && dram_stall && (m1_rd_addr != 5'd0) && (m1_rd_addr == rs1_id);
    wire rs2_match_m1  = rs2_en && m1_mem_re && dram_stall && (m1_rd_addr != 5'd0) && (m1_rd_addr == rs2_id);
    wire load_use_mem1 = rs1_match_m1 || rs2_match_m1;

    wire load_use = load_use_ex1 || load_use_ex2 || load_use_mem1;

    // 停顿前端load-use时冻结IF/ID，防止依赖指令进入EX1
    assign stall = load_use;

    // 冲刷IF/ID：分支跳转时，PC+4处取出的指令是错的
    assign flush_if_id = e2_pc_sel;

    // 冲刷ID/EX1：load-use插入气泡或分支跳转清除第二条错误指令
    assign flush_id_ex1 = load_use || e2_pc_sel;

endmodule
