/* `include "../include/defines.vh"

module hazard_unit (
    input  wire [31:0] instr_id,     // ID 级指令
    input  wire [31:0] instr_ex,     // EX 级指令
    input  wire        mem_re_ex,    // EX 级 Load 标志
    input  wire        pc_sel,       // 分支/跳转决策（顶层）
    output wire        stall,        // =1: PC 和 IF/ID 保持
    //output wire        flush,        // =1: ID/EX 清零
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
  //wire is_J = (instr_id[6:0] == 7'b110_1111) | (instr_id[6:0] == 7'b110_0111);  // JAL|JALR
  wire is_JAL = instr_id[6:0] == 7'b110_1111;  // JAL
  wire is_JALR = instr_id[6:0] == 7'b110_0111;  // JALR
  wire is_branch_id = (instr_id[6:0] == 7'b110_0011) | is_JAL | is_JALR;  // BEQ|BNE|BLT|BGE|BLTU|BGEU|JAL|JALR

  wire branch_hazard = is_branch_id && reg_we_ex && (rd_ex != 5'd0) && 
                         ((((rd_ex == rs1_id) || (rd_ex == rs2_id)) && !(is_JAL|is_JALR))|((rd_ex == rs1_id)&&is_JALR));  // JALR 仅依赖 rs1

  // 综合 Stall 和 Flush 信号
  assign stall = load_use | branch_hazard;

  // 只有发生实际跳转时，才清空 IF/ID 阶段的指令（避免误杀正常取指）
  assign flush_if_id = pc_sel;

  // 发生 Load-Use/Branch 冒险需要插入气泡，或者发生跳转时，清空 ID/EX 寄存器
  assign flush_id_ex = load_use | branch_hazard | pc_sel;

endmodule
 */

`include "../include/defines.vh"

module hazard_unit (
    input wire [31:0] instr_id,  // ID 级指令
    input wire [31:0] instr_ex,  // EX 级指令
    input wire mem_re_ex,  // EX 级 Load 标志（mem_read_enable）
    input wire pc_sel,  // 来自 EX 阶段的最终跳转决策信号，无用可删除
    output wire stall,  // =1: 冻结 PC 和 IF/ID 寄存器
    output wire flush_if_id,  // =1: 清空 IF/ID 寄存器
    output wire flush_id_ex,  // =1: 清空 ID/EX 寄存器
    input wire reg_we_ex,  // EX 级写使能

    input wire predict_wrong  // 预测错误时需要清空 IF/ID 和 ID/EX 寄存器，防止错误指令进入后续阶段
);
  // 1. 字段提取
  wire [4:0] rs1_id = instr_id[19:15];
  wire [4:0] rs2_id = instr_id[24:20];
  wire [4:0] rd_ex = instr_ex[11:7];
  //防止在非分支指令中误判预测错误导致不必要的停顿和指令清空
  wire is_branch_id = (instr_ex[6:0] == 7'b110_0011) | (instr_ex[6:0] == 7'b110_1111) | (instr_ex[6:0] == 7'b110_0111);  // BEQ|BNE|BLT|BGE|BLTU|BGEU|JAL|JALR

  // 2. Load-Use 冒险检测
  // 如果 EX 阶段是 Load 指令，且其目的寄存器 rd 是 ID 阶段指令的源寄存器
  // 这是唯一需要 Stall（暂停）的情况。
  wire load_use = mem_re_ex && (rd_ex != 5'd0) && ((rd_ex == rs1_id) || (rd_ex == rs2_id));

  // 3. 分支数据冒险（注意！）
  // 由于 branch_comp 移到了 EX 阶段，它可以直接利用 EX 阶段的前递逻辑
  // 就像 ADD 指令一样。因此，不再需要专门的 branch_hazard 暂停逻辑。
  // 分支指令会在进入 EX 阶段时，通过前递拿到最新的 rs1 和 rs2 值进行比较。

  // --- 信号综合 ---

  // 只有 Load-Use 冲突时需要暂停
  assign stall = load_use;

  // 发生预测错误时也需要冲刷指令
  // 冲刷不再由pc_sel决定，而是由predict_wrong决定
  assign flush_if_id = is_branch_id && predict_wrong;  // 预测错误时清空 IF/ID 寄存器

  // ID/EX 寄存器在两种情况下需要清零（插入气泡）：
  // 1. 发生 Load-Use 冲突，需要停一拍。
  // 2. 预测错误，需要冲刷掉 ID 段的指令。
  assign flush_id_ex = load_use | (is_branch_id && predict_wrong);  // 预测错误时清空 ID/EX 寄存器

endmodule
