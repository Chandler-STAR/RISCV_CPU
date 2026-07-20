`include "../include/defines.vh"
// 检测 Load-Use 冲突： load(或流水化乘法)与 ID 阶段指令的源寄存器
// 重叠时，停顿前端、向 EX1 插入气泡，直到数据可转发为止
// store-buffer / L0 提前查表等快速路径命中的 load 数据提前就绪，相应少停或不停
// 跳转改向的冲刷由顶层误预测信号统一驱动,本模块只管停顿,不管冲刷
module hazard_unit (
    // ID阶段——后续指令（被检测是否依赖in-flight load）
    input  wire [ 4:0] rs1_id,          // ID阶段rs1地址
    input  wire [ 4:0] rs2_id,          // ID阶段rs2地址
    input  wire        rs1_en,          // ID指令是否真正使用rs1
    input  wire        rs2_en,          // ID指令是否真正使用rs2

    // EX1阶段——load在此阶段，数据3拍后到WB
    input  wire [ 4:0] e1_rd_addr,
    input  wire        e1_mem_re,       // EX1是否为load指令
    input  wire        e1_is_mul,       // 流水化乘法,结果就绪时机与 load 同形(两级后才可转发)
    input  wire        d1_hit,       // EX1 的 load 已提前查缓冲命中(数据下拍即可转发)→不停

    // EX2阶段——load在此阶段，数据2拍后到WB
    input  wire [ 4:0] e2_rd_addr,
    input  wire        e2_mem_re,
    input  wire        e2_ld_ok,       // EX2 的 load 数据下拍在 MEM1 就能转发(缓冲命中/直传/投机读),不必停顿
    input  wire        e2_is_pmul,      // 流水化乘法在 EX2

    // MEM1阶段——load在此阶段，dram_driver寄存器使数据延迟1拍
    input  wire [ 4:0] m1_rd_addr,
    input  wire        m1_mem_re,
    input  wire        dram_stall,      // DRAM停顿时数据未到WB，仍需暂停

    output wire        stall            // 停顿IF/ID（冻结PC和IF/ID寄存器）
);

    // Load-Use:只对真正使用 rs1/rs2 的指令检查对应源寄存器(乘法按 load 同形规则参与;提前命中的免停)
    wire e1_lat_op = (e1_mem_re && !d1_hit) || e1_is_mul;
    wire rs1_match_ex1  = rs1_en && e1_lat_op && (e1_rd_addr != 5'd0) && (e1_rd_addr == rs1_id);
    wire rs2_match_ex1  = rs2_en && e1_lat_op && (e1_rd_addr != 5'd0) && (e1_rd_addr == rs2_id);
    wire load_use_ex1   = rs1_match_ex1 || rs2_match_ex1;

    wire e2_lat_op = (e2_mem_re && !e2_ld_ok) || e2_is_pmul;   // 数据下一拍就有的不用停,从MEM1那排寄存器转发即可
    wire rs1_match_ex2  = rs1_en && e2_lat_op && (e2_rd_addr != 5'd0) && (e2_rd_addr == rs1_id);
    wire rs2_match_ex2  = rs2_en && e2_lat_op && (e2_rd_addr != 5'd0) && (e2_rd_addr == rs2_id);
    wire load_use_ex2   = rs1_match_ex2 || rs2_match_ex2;

    // 慢路径load(没赶上提前读,dram_stall亮):它到MEM1才发地址,数据还差2拍才能转发

    wire rs1_match_m1  = rs1_en && m1_mem_re && dram_stall && (m1_rd_addr != 5'd0) && (m1_rd_addr == rs1_id);
    wire rs2_match_m1  = rs2_en && m1_mem_re && dram_stall && (m1_rd_addr != 5'd0) && (m1_rd_addr == rs2_id);
    wire load_use_mem1 = rs1_match_m1 || rs2_match_m1;

    wire load_use = load_use_ex1 || load_use_ex2 || load_use_mem1;

    // 停顿归因(按来源拆;再分 load/mul)
    wire e1_ld_only  = e1_mem_re && !d1_hit;
    wire e1_match_any = rs1_match_ex1 || rs2_match_ex1;
    wire e2_match_any = rs1_match_ex2 || rs2_match_ex2;

    // 停顿前端load-use时冻结IF/ID，防止依赖指令进入EX1
    assign stall = load_use;

endmodule
