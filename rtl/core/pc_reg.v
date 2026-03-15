module Pc_reg (
    input clk,
    input rst_n,
    input stall,
    //跳转
    input flush,
    input [31:0] pc_branch_target,
    //输出指令地址
    output reg [31:0] pc_out
);
  always @(posedge clk) begin
    if (rst_n) begin
      pc_out <= 32'd0;
    end else if (flush) begin
      pc_out <= pc_branch_target;
    end else if (~stall) begin
      pc_out <= pc_out + 32'd4;
    end
  end

endmodule
