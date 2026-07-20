`include "../include/defines.vh"
// pmul: 流水线乘法器,3拍出结果
//
// 原理和手算竖式乘法一样:32位x32位太大,FPGA的DSP硬件一次乘不动,
// 就把每个数拆成高低两半,交叉乘出4个小乘积(高x高、高x低、低x高、低x低),
// 再按位置错位加起来,等于原来的大乘法。
// 一拍算不完就拆成3拍流水:EX1拍存操作数 -> EX2拍算4个小乘积 -> MEM1拍加总。
// 这样流水线不用停下来等乘法,只是结果晚两拍才能拿,和load差不多,
// 所以停顿和转发规则直接复用load那一套。
//
// 4条乘法指令的区别只在"操作数当有符号还是无符号、取结果的高32还是低32位":
// 统一办法是把32位扩成33位(无符号补0,有符号复制符号位),之后全按有符号乘,
// 四条指令就走同一条通路了。
module pmul (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall_back,     // MEM1 反压:所有 pmul 寄存器保持
    input  wire        flush,          // = predict_wrong | trap_redirect | mdu_stall

    // EX1侧输入
    input  wire        e1_is_mul,      // EX1 是一条 mul/mulh/mulhsu/mulhu
    input  wire [ 4:0] e1_alu_op,
    input  wire [31:0] e1_a,           // 已转发的 rs1
    input  wire [31:0] e1_b,           // 已转发的 rs2

    // 标志位,给forward_unit/hazard_unit判断乘法结果好没好
    output reg         e2_is_pmul,
    output reg         m1_is_pmul,

    // 结果,MEM1拍出来
    output wire [31:0] pmul_out
);

  reg  [31:0] pmul_a_r, pmul_b_r;
  reg         pmul_asgn_r, pmul_bsgn_r;
  reg         e2_pmul_hi, m1_mul_hi;
  reg  signed [31:0] pmul_hh_r;
  reg  signed [33:0] pmul_hl_r, pmul_lh_r;
  reg         [33:0] pmul_ll_r;

  wire pmul_hi_dec = (e1_alu_op == `ALU_MULH) || (e1_alu_op == `ALU_MULHSU) || (e1_alu_op == `ALU_MULHU);
  wire pmul_asgn   = (e1_alu_op == `ALU_MUL)  || (e1_alu_op == `ALU_MULH)   || (e1_alu_op == `ALU_MULHSU);
  wire pmul_bsgn   = (e1_alu_op == `ALU_MUL)  || (e1_alu_op == `ALU_MULH);

  // EX1拍:存下操作数
  always @(posedge clk) begin
    if (rst) begin
      pmul_a_r <= 32'h0;  pmul_b_r <= 32'h0;
      pmul_asgn_r <= 1'b0; pmul_bsgn_r <= 1'b0;
    end else if (e1_is_mul && !stall_back) begin
      pmul_a_r    <= e1_a;
      pmul_b_r    <= e1_b;
      pmul_asgn_r <= pmul_asgn;
      pmul_bsgn_r <= pmul_bsgn;
    end
  end

  // 标志位跟着流水线走:stall时保持,flush时清零(和ex1_ex2_reg一个规矩)
  always @(posedge clk) begin
    if (rst) begin e2_is_pmul <= 1'b0; e2_pmul_hi <= 1'b0; end
    else if (!stall_back) begin
      if (flush) e2_is_pmul <= 1'b0;
      else begin e2_is_pmul <= e1_is_mul; e2_pmul_hi <= pmul_hi_dec; end
    end
  end

  // 33位扩展:无符号指令补0,有符号指令复制最高位(这样统一按有符号处理)
  // 然后拆成两半:高16位(带符号) + 低17位(不带符号)
  wire [32:0] pmul_a33 = {pmul_asgn_r & pmul_a_r[31], pmul_a_r};
  wire [32:0] pmul_b33 = {pmul_bsgn_r & pmul_b_r[31], pmul_b_r};
  wire signed [15:0] pmul_ah = pmul_a33[32:17];
  wire        [16:0] pmul_al = pmul_a33[16:0];
  wire signed [15:0] pmul_bh = pmul_b33[32:17];
  wire        [16:0] pmul_bl = pmul_b33[16:0];

  always @(posedge clk) begin
    if (e2_is_pmul && !stall_back) begin
      pmul_hh_r <= pmul_ah * pmul_bh;                     // 高x高
      pmul_hl_r <= pmul_ah * $signed({1'b0, pmul_bl});    // 高x低
      pmul_lh_r <= $signed({1'b0, pmul_al}) * pmul_bh;    // 低x高
      pmul_ll_r <= pmul_al * pmul_bl;                     // 低x低
    end
  end

  always @(posedge clk) begin
    if (rst) begin m1_is_pmul <= 1'b0; m1_mul_hi <= 1'b0; end
    else if (!stall_back) begin m1_is_pmul <= e2_is_pmul; m1_mul_hi <= e2_pmul_hi; end
  end

  // MEM1拍:把4个小乘积按位置错位加回去(竖式乘法的进位相加)
  // 高x高要左移34位,中间两个左移17位,低x低不移
  wire signed [64:0] pmul_cat = ($signed({{33{pmul_hh_r[31]}}, pmul_hh_r}) <<< 34)
                              | $signed({31'd0, pmul_ll_r});
  wire signed [34:0] pmul_mid = $signed({pmul_hl_r[33], pmul_hl_r})
                              + $signed({pmul_lh_r[33], pmul_lh_r});
  wire signed [64:0] pmul_sum = pmul_cat + ($signed({{30{pmul_mid[34]}}, pmul_mid}) <<< 17);

  assign pmul_out = m1_mul_hi ? pmul_sum[63:32] : pmul_sum[31:0];

endmodule
