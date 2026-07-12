`include "../include/defines.vh"
// mdu —— 乘除单元中的除法部分(恢复余数法,每位两拍)
// 乘法由 pmul.v 承担;本单元只做 div/divu/rem/remu。
// start 由外部保证仅在 IDLE 时拉高一拍(myCPU 的 mdu_start = e1_is_div & ...)。
module mdu (
    input  wire        clk,
    input  wire        rst,

    input  wire        start,        // 1 拍脉冲
    input  wire [ 4:0] alu_op,       // ALU_DIV ~ ALU_REMU
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        flush,        // trap / 分支冲刷时取消

    output reg         busy,
    output reg         done,         // 1 拍脉冲（外部用 done_held 拓宽）
    output reg  [31:0] result
);

  // ============ 操作码识别 ============
  wire is_div   = (alu_op == `ALU_DIV);
  wire is_divu  = (alu_op == `ALU_DIVU);
  wire is_rem   = (alu_op == `ALU_REM);
  wire is_remu  = (alu_op == `ALU_REMU);
  wire is_any_div = is_div | is_divu | is_rem | is_remu;
  wire div_signed = is_div | is_rem;

  // ============ 状态机 ============
  localparam S_IDLE     = 4'd0;
  localparam S_DIV_PREP = 4'd3;
  localparam S_DIV_RUN  = 4'd4;
  localparam S_DIV_FIX  = 4'd5;

  reg [3:0] state;

  // ============ 除法 ============
  reg [31:0] div_dividend_r;                    // 被除数寄存器（捕获输入）
  reg [31:0] div_divisor_r;                     // 除数寄存器（捕获输入，除法过程中不变）
  reg        div_q_neg_r;                       // 商结果符号（是否需要对商取反）
  reg        div_r_neg_r;                       // 余数结果符号（是否需要对余数取反）
  reg        div_need_rem_r;                    // 本次需要余数（is_rem 或 is_remu）
  reg        div_is_divu_r;
  reg        div_by_zero_r;                     // 除数为零标志
  reg        div_overflow_r;                    // 除法溢出标志（仅有符号除法 a=-2^31 b=-1 会溢出）
  reg [63:0] div_acc;                           // 除法运算寄存器（高 32 位为部分余数，低 32 位为被除数剩余位,商从最低位逐位移入）
  reg [5:0]  div_cnt;                           // 除法运算计数器（最多 32 次）
  reg        div_phase;                         // 除法迭代拆两拍(0=减法打拍,1=用寄存结果移位)
  reg [32:0] div_sub_r;                         // 打拍的部分余数减法结果

  wire [32:0] div_sub = div_acc[63:31] - {1'b0, div_divisor_r};

  // ============ 状态转移 ============
  always @(posedge clk) begin
    if (rst) begin
      state    <= S_IDLE;
      busy     <= 1'b0;
      done     <= 1'b0;
      result   <= 32'h0;
      div_acc  <= 64'd0;
      div_cnt  <= 6'd0;
      div_phase <= 1'b0;
      div_sub_r <= 33'd0;
    end else if (flush) begin
      state <= S_IDLE;
      busy  <= 1'b0;
      done  <= 1'b0;
    end else begin
      done <= 1'b0;  // 默认 done=0
      case (state)
        // -------------------------------------------------------------
        S_IDLE: begin
          if (start && is_any_div) begin
            div_dividend_r <= a;                        // 被除数捕获
            div_divisor_r  <= div_signed ? (b[31] ? (~b + 32'd1) : b) : b;  // 除数捕获（有符号除法需要先取绝对值）
            div_q_neg_r    <= div_signed ? ((a[31] ^ b[31]) & (b != 32'd0)) : 1'b0;// 商符号（异号且除数不为0时商为负）
            div_r_neg_r    <= div_signed ? a[31] : 1'b0;                        // 余数符号（有符号除法且被除数为负时余数为负）
            div_need_rem_r <= is_rem | is_remu;                                 // 是否需要计算余数
            div_is_divu_r  <= is_divu;
            div_by_zero_r  <= (b == 32'd0);                 // 除数为零标志         
            div_overflow_r <= div_signed & (a == 32'h8000_0000) & (b == 32'hFFFF_FFFF);// 除法溢出标志
            div_acc        <= {32'd0, div_signed ? (a[31] ? (~a + 32'd1) : a) : a}; // 初始值:高 32 位(余数)清 0,低 32 位装被除数绝对值
            div_cnt        <= 6'd32;                            // 除法运算需要 32 次移位
            div_phase      <= 1'b0;                             // 两拍迭代从减法拍开始
            state          <= S_DIV_PREP;                           // 除法准备阶段：检查特殊情况（除数为零或除法溢出）
            busy           <= 1'b1;                                 // 除法从 PREP 开始就算 busy 了，DIV_RUN 和 DIV_FIX 只是运算过程和结果修正
          end
        end

        // -------------------------------------------------------------
        // 除法
        S_DIV_PREP: begin                                                   // 除法准备阶段：检查除数为零或除法溢出等特殊情况，决定直接进入结果修正还是进入正常的除法运算
          if (div_by_zero_r | div_overflow_r) state <= S_DIV_FIX;
          else                                state <= S_DIV_RUN;
        end
        S_DIV_RUN: begin                        // 除法运算阶段:恢复余数法,每位拆两拍——
          // 先打拍存减法结果(断开长借位链与移位选择的组合串联),下一拍用寄存结果移位。
          // 延迟翻倍,但程序里除法极少,对总时间影响可以忽略,换来的是主频不被除法器拖累。
          if (div_cnt == 6'd0) begin                // 除法运算完成，进入结果修正阶段
            state <= S_DIV_FIX;
          end else if (!div_phase) begin        // phase0:寄存部分余数减法结果
            div_sub_r <= div_sub;
            div_phase <= 1'b1;
          end else begin                        // phase1:按寄存的借位位移位
            if (!div_sub_r[32]) div_acc <= {div_sub_r[31:0], div_acc[30:0], 1'b1};
            else                div_acc <= {div_acc[62:0], 1'b0};
            div_cnt   <= div_cnt - 6'd1;
            div_phase <= 1'b0;
          end
        end
        S_DIV_FIX: begin
          if (div_by_zero_r) begin
            // RISC-V 规范：除以 0 时 DIV 与 DIVU 的商都为 0xFFFFFFFF（全 1），余数为被除数
            result <= div_need_rem_r ? div_dividend_r : 32'hFFFF_FFFF;
          end else if (div_overflow_r) begin                                            // 有符号除法溢出时商为 0x8000_0000，余数为 0
            result <= div_need_rem_r ? 32'd0 : 32'h8000_0000;               
          end else if (div_need_rem_r) begin                            // 需要余数时输出余数（根据符号位决定是否取反）
            result <= div_r_neg_r ? (~div_acc[63:32] + 32'd1) : div_acc[63:32];
          end else begin                                                            // 不需要余数时输出商（根据符号位决定是否取反）
            result <= div_q_neg_r ? (~div_acc[31:0] + 32'd1) : div_acc[31:0];
          end
          done  <= 1'b1;
          busy  <= 1'b0;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule
