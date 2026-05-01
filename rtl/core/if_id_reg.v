`include "../include/defines.vh"

module if_id_reg (
    input clk,
    input rst,
    input flush_if_id,  // 来自 hazard_unit 的 IF/ID 专用 Flush 信号
    input stall,
    // 来自 pc_reg 的当前 PC 和 PC+4
    input [31:0] pc_in,
    input [31:0] pc4_in,
    // 来自 imem 的指令
    input [31:0] instr_in,
    // 来自分支预测器的预测结果
    input wire predict_taken_in,
    input wire [31:0] predict_target_in,
    // 输出到 id 阶段的 PC、PC+4 和指令
    output reg [31:0] d_pc,
    output reg [31:0] d_pc4,
    output reg [31:0] d_instr,
    // 输出到 ID 阶段的分支预测结果
    output reg d_predict_taken,
    output reg [31:0] d_predict_target
);

  //优先相应rst，其次是stall，再次是flush，最后正常更新寄存器
  always @(posedge clk) begin
    if (rst) begin
      d_pc <= 0;
      d_pc4 <= 0;
      d_instr <= `INST_NOP;
      d_predict_taken <= 0;
      d_predict_target <= 32'b0;
    end else if (flush_if_id) begin  // Flush 应该优先于 Stall
      d_pc <= 0;
      d_pc4 <= 0;
      d_instr <= `INST_NOP;
      d_predict_taken <= 0;
      d_predict_target <= 32'b0;
    end else if (stall) begin
      d_pc <= d_pc;
      d_pc4 <= d_pc4;
      d_instr <= d_instr;
      d_predict_taken <= d_predict_taken;
      d_predict_target <= d_predict_target;
    end else begin
      d_pc <= pc_in;
      d_pc4 <= pc4_in;
      d_instr <= instr_in;
      d_predict_taken <= predict_taken_in;
      d_predict_target <= predict_target_in;
    end
  end

endmodule
