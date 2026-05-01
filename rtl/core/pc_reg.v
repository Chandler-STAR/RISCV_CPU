module pc_reg (
    input clk,
    input rst,
    input stall,
    // 下一 PC，来自顶层 PC MUX 输出（pc_sel ? pc_branch : pc4）
    input [31:0] pc_next,
    // 当前 PC → imem.pc 和 if_id_reg.pc_in
    output reg [31:0] pc,
    // PC+4 → if_id_reg.pc4_in（assign pc4 = pc + 32'd4）
    output wire [31:0] pc4 
);

  assign pc4 = pc + 32'd4;

  always @(posedge clk) begin
    if (rst) begin
      pc <= 32'h8000_0000;  // 复位时 PC 初始化为 0x8000_0000
    end else if (!stall) begin
      pc <= pc_next;
    end
  end
endmodule
