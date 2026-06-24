`include "../include/defines.vh"
// 乘除单元（Multiply-Divide Unit）
// - 乘法：3 拍（IDLE 拍捕获操作数 → S1 一拍完成乘法（DSP A/B reg → M reg）→ DONE 一拍选高低半字）
// - 除法：~35 拍（PREP 1 拍 → 32 拍移位除法 → FIX 1 拍输出）
// 启动条件由外部 start 给出（保证仅在 IDLE 时拉高一拍）
module mdu (
    input  wire        clk,
    input  wire        rst,

    input  wire        start,        // 1 拍脉冲
    input  wire [ 4:0] alu_op,       // ALU_MUL ~ ALU_REMU
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        flush,        // trap / 分支冲刷时取消

    output reg         busy,
    output reg         done,         // 1 拍脉冲（外部用 done_held 拓宽）
    output reg  [31:0] result
);

  // ============ 操作码识别 ============
  wire is_mul    = (alu_op == `ALU_MUL);
  wire is_mulh   = (alu_op == `ALU_MULH);
  wire is_mulhsu = (alu_op == `ALU_MULHSU);
  wire is_mulhu  = (alu_op == `ALU_MULHU);
  wire is_any_mul = is_mul | is_mulh | is_mulhsu | is_mulhu;

  wire is_div   = (alu_op == `ALU_DIV);
  wire is_divu  = (alu_op == `ALU_DIVU);
  wire is_rem   = (alu_op == `ALU_REM);
  wire is_remu  = (alu_op == `ALU_REMU);
  wire is_any_div = is_div | is_divu | is_rem | is_remu;
  wire div_signed = is_div | is_rem;

  // ============ 状态机 ============
  localparam S_IDLE     = 4'd0;
  localparam S_MUL_S1   = 4'd1;
  localparam S_MUL_DONE = 4'd2;
  localparam S_DIV_PREP = 4'd3;
  localparam S_DIV_RUN  = 4'd4;
  localparam S_DIV_FIX  = 4'd5;

  reg [3:0] state;

  // ============ 乘法 ============
  // mul_a_r / mul_b_r 映射到 DSP A/B 寄存器；mul_p_r 映射到 M/P 寄存器
  reg [31:0] mul_a_r, mul_b_r;                      // 乘数寄存器（捕获输入）
  reg        mul_a_sign_r, mul_b_sign_r;            // 乘数符号（是否需要符号扩展到 33 位）
  reg        mul_take_hi_r;                         // 乘法结果选择：0=取低 32 位，1=取高 32 位
  reg signed [64:0] mul_p_r;                        // 乘积寄存器（65 位，包含符号位，方便有符号乘法）

  // ============ 除法 ============
  reg [31:0] div_dividend_r;                    // 被除数寄存器（捕获输入）
  reg [31:0] div_divisor_r;                     // 除数寄存器（捕获输入，除法过程中不变）
  reg        div_q_neg_r;                       // 商结果符号（是否需要对商取反）
  reg        div_r_neg_r;                       // 余数结果符号（是否需要对余数取反）
  reg        div_need_rem_r;                    // 本次需要余数（is_rem 或 is_remu）
  reg        div_is_divu_r;
  reg        div_by_zero_r;                     // 除数为零标志
  reg        div_overflow_r;                    // 除法溢出标志（仅有符号除法 a=-2^31 b=-1 会溢出）
  reg [63:0] div_acc;                           // 除法运算寄存器（高 32 位为部分商，低 32 位为部分余数）   
  reg [5:0]  div_cnt;                           // 除法运算计数器（最多 32 次）

  wire [32:0] div_sub = div_acc[63:31] - {1'b0, div_divisor_r};

  // ============ 状态转移 ============
  always @(posedge clk) begin
    if (rst) begin
      state    <= S_IDLE;
      busy     <= 1'b0;
      done     <= 1'b0;
      result   <= 32'h0;
      mul_p_r  <= 65'd0;
      div_acc  <= 64'd0;
      div_cnt  <= 6'd0;
    end else if (flush) begin
      state <= S_IDLE;
      busy  <= 1'b0;
      done  <= 1'b0;
    end else begin
      done <= 1'b0;  // 默认 done=0
      case (state)
        // -------------------------------------------------------------
        S_IDLE: begin
          if (start && is_any_mul) begin
            mul_a_r       <= a;                             // 乘数 A 捕获
            mul_b_r       <= b;                             // 乘数 B 捕获
            mul_a_sign_r  <= is_mul | is_mulh | is_mulhsu;  // 是否需要符号扩展 A（乘法且有符号）
            mul_b_sign_r  <= is_mul | is_mulh;              // 是否需要符号扩展 B（乘法且有符号，mulhsu 不需要）
            mul_take_hi_r <= is_mulh | is_mulhsu | is_mulhu;// 是否取高 32 位（mulh* 都取高位，mul 取低位）
            state <= S_MUL_S1;                              // 乘法第一拍：计算乘积
            busy  <= 1'b1;                              // 注意：乘法在 S_MUL_S1 就算 busy 了，S_MUL_DONE 只是取结果并 done
          end else if (start && is_any_div) begin
            div_dividend_r <= a;                        // 被除数捕获
            div_divisor_r  <= div_signed ? (b[31] ? (~b + 32'd1) : b) : b;  // 除数捕获（有符号除法需要先取绝对值）
            div_q_neg_r    <= div_signed ? ((a[31] ^ b[31]) & (b != 32'd0)) : 1'b0;// 商符号（异号且除数不为0时商为负）
            div_r_neg_r    <= div_signed ? a[31] : 1'b0;                        // 余数符号（有符号除法且被除数为负时余数为负）
            div_need_rem_r <= is_rem | is_remu;                                 // 是否需要计算余数
            div_is_divu_r  <= is_divu;
            div_by_zero_r  <= (b == 32'd0);                 // 除数为零标志         
            div_overflow_r <= div_signed & (a == 32'h8000_0000) & (b == 32'hFFFF_FFFF);// 除法溢出标志
            div_acc        <= {32'd0, div_signed ? (a[31] ? (~a + 32'd1) : a) : a}; // 除法运算寄存器初始值（部分商=0，部分余数=被除数绝对值）
            div_cnt        <= 6'd32;                            // 除法运算需要 32 次移位
            state          <= S_DIV_PREP;                           // 除法准备阶段：检查特殊情况（除数为零或除法溢出）
            busy           <= 1'b1;                                 // 除法从 PREP 开始就算 busy 了，DIV_RUN 和 DIV_FIX 只是运算过程和结果修正
          end
        end

        // -------------------------------------------------------------
        // 乘法（2 拍：S1 计算 → DONE 取段并 done）
        S_MUL_S1: begin                                         // 乘法计算拍：根据符号位扩展到 33 位（最高位为符号位），送入乘法器（DSP 寄存器）
          mul_p_r <= $signed({mul_a_sign_r & mul_a_r[31], mul_a_r}) *
                     $signed({mul_b_sign_r & mul_b_r[31], mul_b_r});
          state <= S_MUL_DONE;
        end
        S_MUL_DONE: begin                                               // 乘法结果拍：根据指令选择高低半字输出，done
          result <= mul_take_hi_r ? mul_p_r[63:32] : mul_p_r[31:0];
          done   <= 1'b1;
          busy   <= 1'b0;
          state  <= S_IDLE;
        end

        // -------------------------------------------------------------
        // 除法
        S_DIV_PREP: begin                                                   // 除法准备阶段：检查除数为零或除法溢出等特殊情况，决定直接进入结果修正还是进入正常的除法运算
          if (div_by_zero_r | div_overflow_r) state <= S_DIV_FIX;
          else                                state <= S_DIV_RUN;
        end
        S_DIV_RUN: begin                        // 除法运算阶段：使用恢复余数法进行除法运算，每拍移位一次，持续 32 拍
          if (div_cnt == 6'd0) begin                // 除法运算完成，进入结果修正阶段
            state <= S_DIV_FIX;
          end else begin                        // 除法运算未完成，继续移位运算
            if (!div_sub[32]) div_acc <= {div_sub[31:0], div_acc[30:0], 1'b1};      // 部分余数减去除数，如果结果非负（div_sub[32] == 0），则部分商末尾置 1，部分余数更新为减法结果
            else              div_acc <= {div_acc[62:0], 1'b0};         // 部分余数非负（div_sub[32] == 1），则部分商末尾置 0，部分余数保持不变（相当于加回除数）
            div_cnt <= div_cnt - 6'd1;          // 继续下一轮移位运算，直到 div_cnt 计数到 0    
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
