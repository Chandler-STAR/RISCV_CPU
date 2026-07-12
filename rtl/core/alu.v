`include "../include/defines.vh"

//M 扩展由独立的 mdu.v、pmul.v 处理，结果在顶层 mux。
//此处仅仅是起到占位作用，保持接口一致，方便后续扩展。

module alu (
    input wire [31:0] alu_a,
    input wire [31:0] alu_b,
    input  wire [4:0]  alu_op,  // 来自控制单元的 ALU 操作码，全局定义在 defines.vh 中
    output reg [31:0] alu_out
);
  wire [4:0] shamt = alu_b[4:0];  // 移位量取低 5 位

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
      //M 扩展走独立 mdu.v/pmul.v，alu_out 此处占位 
      `ALU_MUL,
      `ALU_MULH,
      `ALU_MULHU,
      `ALU_MULHSU,
      `ALU_DIV,
      `ALU_DIVU,
      `ALU_REM,
      `ALU_REMU:   alu_out = 32'h0;
      //扩展槽位:BEXT0-2 已启用为 Zba 移位加slli+add 融合
      //Zba拓展指令集（地址生成指令扩展）含SH1ADD，SH2ADD，SH3ADD，rs1左移1，2，3位后相加
      `ALU_BEXT0:  alu_out = {alu_a[30:0], 1'b0}   + alu_b;  // sh1add
      `ALU_BEXT1:  alu_out = {alu_a[29:0], 2'b00}  + alu_b;  // sh2add
      `ALU_BEXT2:  alu_out = {alu_a[28:0], 3'b000} + alu_b;  // sh3add
      //现场添加指令 : 把32'h0换成抽中指令的表达式
      //   andn: alu_a & ~alu_b     orn: alu_a | ~alu_b    xnor: ~(alu_a ^ alu_b)
      //   max : ($signed(alu_a) > $signed(alu_b)) ? alu_a : alu_b
      //   rori: (alu_b[4:0]==0) ? alu_a : ({alu_a,alu_a} >> alu_b[4:0])
      `ALU_BEXT3:  alu_out = 32'h0;   // 保留,比赛当天换表达式


      default:    alu_out = 32'h0;  // 默认输出0
    endcase
  end


endmodule
