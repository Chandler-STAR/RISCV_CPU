`include "../include/defines.vh"
// Trap 控制单元：识别 EX1 阶段的 ecall / mret，
// 产生 trap_taken / mret_taken 与 PC 重定向信号
module trap_ctrl (
    input  wire        e1_is_ecall,     // EX1 阶段当前指令是 ecall
    input  wire        e1_is_mret,      // EX1 阶段当前指令是 mret
    input  wire [31:0] e1_pc,           // EX1 阶段 PC（用来写 mepc）  
    input  wire        stall_back,     // 后端停顿时不触发 trap，等下一拍
    input  wire        predict_wrong,  // EX2 分支预测错误：当前 EX1 是错误路径
    input  wire [31:0] mtvec,           // 当前 mtvec 值（用来 trap_target）
    input  wire [31:0] mepc,            // 当前 mepc 值（用来 trap_target）

    output wire        trap_taken,  // 本拍发生 trap（ecall 且非停顿且非预测错误）
    output wire        mret_taken,// 本拍发生 mret（mret 且非停顿且非预测错误）
    output wire [31:0] trap_cause,      // trap 原因码（目前仅支持 ecall，固定为 `CAUSE_ECALL_M）
    output wire [31:0] trap_pc,        // 触发指令 PC，用来写 mepc
    output wire        trap_redirect,  // 给 PC 通路的 redirect 信号
    output wire [31:0] trap_target     // mtvec 或 mepc
);

  // 后端停顿或 EX1 是错误路径时，不允许 trap 副作用
  assign trap_taken    = e1_is_ecall & ~stall_back & ~predict_wrong;        // 只有当 EX1 指令是 ecall，且当前没有后端停顿，且当前不是分支预测错误路径时，才触发 trap
  assign mret_taken    = e1_is_mret  & ~stall_back & ~predict_wrong;        // 只有当 EX1 指令是 mret，且当前没有后端停顿，且当前不是分支预测错误路径时，才触发 mret
  assign trap_cause    = `CAUSE_ECALL_M;                    // trap 原因码固定为 ecall（机器模式）
  assign trap_pc       = e1_pc;                        // 触发指令的 PC 直接来自 EX1 阶段的 PC，用于写入 mepc
  assign trap_redirect = trap_taken | mret_taken;       // 发生 trap 或 mret 都需要重定向 PC 通路
  assign trap_target   = trap_taken ? mtvec : mepc;         // trap 目标地址：trap 时为 mtvec，mret 时为 mepc

endmodule
