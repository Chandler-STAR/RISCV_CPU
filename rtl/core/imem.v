module imem #(
    parameter file_path = ".file_path/"
) (
    input [31:0] pc,
    output wire [31:0] instr_if
);

  reg [31:0] instruction_mem[0:1023];

  // 初始化指令rom，不可综合，临时使用，后续通过总线连接instruction_ram实现
  initial begin
    $readmemh(file_path, instruction_mem);
  end
  //纯组合逻辑，根据当前 PC 输出指令
  assign instr_if = instruction_mem[pc[11:2]];

endmodule
