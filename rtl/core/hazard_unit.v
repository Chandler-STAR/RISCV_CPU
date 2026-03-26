`include "hazard_unit.sv"
module hazard_unit (
    input  wire [31:0] instr_id,   // ID 级指令
    input  wire [31:0] instr_ex,   // EX 级指令
    input  wire        mem_re_ex,  // EX 级 Load 标志
    input  wire        pc_sel,     // 分支/跳转决策（顶层）
    output wire        stall,      // =1: PC 和 IF/ID 保持
    output wire        flush       // =1: ID/EX 清零
);
    //字段提取
    wire [4:0] rs1_id = instr_id[19:15];
    wire [4:0] rs2_id = instr_id[24:20];
    wire [4:0] rd_ex  = instr_ex[11:7];

    // Load-Use：EX 是 Load 且 rd 与 ID 的 rs 重叠
    wire load_use = mem_re_ex && (rd_ex != 5'd0) &&
                   ((rd_ex == rs1_id) || (rd_ex == rs2_id));

    assign stall = load_use;
    assign flush = load_use | pc_sel;

endmodule