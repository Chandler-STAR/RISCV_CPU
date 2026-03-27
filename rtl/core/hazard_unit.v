`include "../include/defines.vh"

module hazard_unit (
    input  wire [31:0] instr_id,     // ID 级指令
    input  wire [31:0] instr_ex,     // EX 级指令
    input  wire        mem_re_ex,    // EX 级 Load 标志
    input  wire        pc_sel,       // 分支/跳转决策（顶层）
    output wire        stall,        // =1: PC 和 IF/ID 保持
    output wire        flush,        // =1: ID/EX 清零
    output wire        flush_if_id,  // 【新增】专给 IF/ID 的清空信号
    output wire        flush_id_ex,  // 【新增】专给 ID/EX 的清空信号
    input  wire        reg_we_ex     // 【新增】EX 级寄存器写使能（用于分支冒险）
);
  //字段提取
  wire [4:0] rs1_id = instr_id[19:15];
  wire [4:0] rs2_id = instr_id[24:20];
  wire [4:0] rd_ex = instr_ex[11:7];

  // Load-Use：EX 是 Load 且 rd 与 ID 的 rs 重叠
  wire load_use = mem_re_ex && (rd_ex != 5'd0) && ((rd_ex == rs1_id) || (rd_ex == rs2_id));

  // 2. 分支数据冒险检测（Branch Data Hazard）
  // 如果 ID 阶段是分支/跳转指令，且它依赖的寄存器正被 EX 阶段计算，必须 Stall
  wire is_branch_id = (instr_id[6:0] == 7'b110_0011) |  // B-type
  (instr_id[6:0] == 7'b110_0111) |  // JALR
  (instr_id[6:0] == 7'b110_1111);  // JAL

  wire branch_hazard = is_branch_id && reg_we_ex && (rd_ex != 5'd0) && 
                         ((rd_ex == rs1_id) || (rd_ex == rs2_id));

  // 综合 Stall 和 Flush 信号
  assign stall = load_use | branch_hazard;

  // 只有发生实际跳转时，才清空 IF/ID 阶段的指令（避免误杀正常取指）
  assign flush_if_id = pc_sel;

  // 发生 Load-Use/Branch 冒险需要插入气泡，或者发生跳转时，清空 ID/EX 寄存器
  assign flush_id_ex = load_use | branch_hazard | pc_sel;

endmodule
