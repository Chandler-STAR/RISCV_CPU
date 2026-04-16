`include "../include/defines.vh"

module regfile (
    input         clk,
    input  [ 4:0] rs1_addr,
    input  [ 4:0] rs2_addr,
    output [31:0] rs1_rf,
    output [31:0] rs2_rf,
    input  [ 4:0] rd_addr,
    input  [31:0] wd,
    input         reg_we
);
  reg [31:0] rf[0:31];
  integer i;

  initial begin
    for (i = 0; i < 32; i = i + 1) begin
      rf[i] = 32'h0;
    end
  end

  assign rs1_rf = (rs1_addr == 5'b0) ? 32'b0 : rf[rs1_addr];  // 读寄存器1，x0寄存器始终为0
  assign rs2_rf = (rs2_addr == 5'b0) ? 32'b0 : rf[rs2_addr];  // 读寄存器2，x0寄存器始终为0


  // 同步写逻辑（保持不变）
  always @(negedge clk) begin   //上升沿改成下降沿，使得readfile提前进行，解决仿真问题
    if (reg_we && rd_addr != 5'b0) begin
      rf[rd_addr] <= wd;
    end
  end


endmodule
