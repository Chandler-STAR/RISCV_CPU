`include "defines.vh"   

module alu (
    input  wire [31:0] alu_a,
    input  wire [31:0] alu_b,
    input  wire [3:0]  alu_op,  // 来自控制单元的 ALU 操作码，全局定义在 defines.vh 中
    output reg  [31:0] alu_out,
    output wire        zero     // alu_ou输出为0的时候为1，辅助调试用的
);
    wire [4:0] shamt = alu_b[4:0];  // 移位量取低 5 位

    always @(*) begin  
        case (alu_op)
            `ALU_ADD  : alu_out = alu_a + alu_b;    // 加法（包括 AUIPC）
            `ALU_SUB  : alu_out = alu_a - alu_b;    // 减法
            `ALU_AND  : alu_out = alu_a & alu_b;    // 与
            `ALU_OR   : alu_out = alu_a | alu_b;    // 或
            `ALU_XOR  : alu_out = alu_a ^ alu_b;    // 异或
            `ALU_SLL  : alu_out = alu_a << shamt;   // 逻辑左移
            `ALU_SRL  : alu_out = alu_a >> shamt;   // 逻辑右移
            `ALU_SRA  : alu_out = $signed(alu_a) >>> shamt; // 算术右移
            `ALU_SLT  : alu_out = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;    // 有符号比较
            `ALU_SLTU : alu_out = (alu_a < alu_b)                   ? 32'd1 : 32'd0;    // 无符号比较
            `ALU_LUI  : alu_out = alu_b;              // 直通 B（LUI）
            `ALU_AUIPC: alu_out = alu_a + alu_b;      // pc + imm
            default   : alu_out = 32'h0;              // 默认输出0
        endcase
    end

    assign zero = (alu_out == 32'h0);   // 输出为0时为1，辅助调试用的   

endmodule