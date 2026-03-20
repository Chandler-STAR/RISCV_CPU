`timescale 1ns / 1ps

module tb_pc_reg;

  // pc_reg Parameters
  parameter PERIOD = 10;


  // pc_reg Inputs
  reg         clk = 0;
  reg         rst = 0;
  reg         stall = 0;
  reg  [31:0] pc_next = 0;
  reg  [31:0] pc_branch = 0;
  reg         pc_sel = 0;

  // pc_reg Outputs
  wire [31:0] pc;
  wire [31:0] pc4;


  initial begin
    forever #(PERIOD / 2) clk = ~clk;
  end

  initial begin
    #(PERIOD * 2) rst = 1;
    #(PERIOD * 2) rst = 0;
    #400 pc_branch = 32'h0000_0004;
    pc_sel = 1;
    #20 pc_sel = 0;
    #200 stall = 1;
    #40 stall = 0;
    #200 $finish;
  end

  //模拟顶层连线
  always @(*) begin
    pc_next = pc_sel ? pc_branch : pc4;
  end

  pc_reg u_pc_reg (
      .clk    (clk),
      .rst    (rst),
      .stall  (stall),
      .pc_next(pc_next[31:0]),

      .pc (pc[31:0]),
      .pc4(pc4[31:0])
  );


endmodule
