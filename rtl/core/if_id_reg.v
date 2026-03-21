`include "../include/defines.vh"

module if_id_reg (
    input clk,
    input rst,
    input flush,
    input stall,
    // 来自 pc_reg 的当前 PC 和 PC+4
    input [31:0] pc_in,
    input [31:0] pc4_in,
    // 来自 imem 的指令
    input [31:0] instr_in,
    // 输出到 id 阶段的 PC、PC+4 和指令
    output reg [31:0] d_pc,
    output reg [31:0] d_pc4,
    output reg [31:0] d_instr
);

  always @(posedge clk) begin
    if (rst || flush) begin
      d_pc <= 0;
      d_pc4 <= 0;
      d_instr <= `INST_NOP;
    end else if (!stall) begin
      d_pc <= pc_in;
      d_pc4 <= pc4_in;
      d_instr <= instr_in;
    end
  end

endmodule
