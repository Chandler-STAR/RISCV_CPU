`include "../include/defines.vh"

//M 扩展由独立的多周期 mdu.v 处理，结果在顶层 mux。
//此处仅仅是起到占位作用，保持接口一致，方便后续扩展。

module alu (
    input wire [31:0] alu_a,
    input wire [31:0] alu_b,
    input  wire [4:0]  alu_op,  // 来自控制单元的 ALU 操作码，全局定义在 defines.vh 中
    output reg [31:0] alu_out
);
  wire [4:0] shamt = alu_b[4:0];  // 移位量取低 5 位

  // 32x32 无进位乘(GF(2)[x] 多项式乘),64 位全积
  function [63:0] f_clmul;
    input [31:0] a;
    input [31:0] b;
    integer i;
    begin
      f_clmul = 64'h0;
      for (i = 0; i < 32; i = i + 1)
        if (b[i]) f_clmul = f_clmul ^ ({32'h0, a} << i);
    end
  endfunction

  wire [63:0] clmul_full = f_clmul(alu_a, alu_b);

  always @(*) begin
    case (alu_op)
      `ALU_ADD:   alu_out = alu_a + alu_b;  // 加法（包括 AUIPC）
      `ALU_SUB:   alu_out = alu_a - alu_b;  // 减法
      `ALU_AND:   alu_out = alu_a & alu_b;  // 与
      `ALU_OR:    alu_out = alu_a | alu_b;  // 或
      `ALU_XOR:   alu_out = alu_a ^ alu_b;  // 异或
      `ALU_SLL:   alu_out = alu_a << shamt;  // 逻辑左移
      `ALU_SRL:   alu_out = alu_a >> shamt;  // 逻辑右移
      `ALU_SRA:   alu_out = $signed(alu_a) >>> shamt;  // 算术右移
      `ALU_SLT:   alu_out = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;  // 有符号比较
      `ALU_SLTU:  alu_out = (alu_a < alu_b) ? 32'd1 : 32'd0;  // 无符号比较
      `ALU_LUI:   alu_out = alu_b;  // 直通 B（LUI）
      `ALU_AUIPC: alu_out = alu_a + alu_b;  // pc + imm

      //Zicsr：CSR 旧值经 B 通路直通到 rd
      `ALU_CSR:    alu_out = alu_b;
      //M 扩展走独立 mdu.v，alu_out 此处占位 
      `ALU_MUL,
      `ALU_MULH,
      `ALU_MULHU,
      `ALU_MULHSU,
      `ALU_DIV,
      `ALU_DIVU,
      `ALU_REM,
      `ALU_REMU:   alu_out = 32'h0;
      //扩展槽位:BEXT0-2 已启用为 Zba 移位加(亦为 slli+add 融合的执行形态)
      `ALU_BEXT0:  alu_out = {alu_a[30:0], 1'b0}   + alu_b;  // sh1add
      `ALU_BEXT1:  alu_out = {alu_a[29:0], 2'b00}  + alu_b;  // sh2add
      `ALU_BEXT2:  alu_out = {alu_a[28:0], 3'b000} + alu_b;  // sh3add
      `ALU_BEXT3:  alu_out = clmul_full[31:0];  // clmul


      default:    alu_out = 32'h0;  // 默认输出0
    endcase
  end


endmodule
