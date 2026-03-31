`timescale 1ps / 1ps


module tb_riscv_top ();
  reg clk;
  reg rst;

  initial begin
    clk = 0;
    forever #10 clk = ~clk;  // 20ps 一个周期，50MHz 时钟
  end

  initial begin
    rst = 1;
    #100 rst = 0;  // 100ps 后释放复位
  end


  riscv_top #(
      .file_path("F:/RISCV_CPU/tests/R_I_test_forward.hex")   //本地测试时需要更改路径
  ) u_riscv_top (
      .clk(clk),
      .rst(rst)
  );

endmodule  //tb_riscv_top
