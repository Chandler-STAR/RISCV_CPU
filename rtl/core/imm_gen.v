module imm_gen (
    input [31:0] d_instr,
    output reg [31:0] imm
);
  //case 语句根据opcode类型提取立即数，并进行符号扩展
  always @(*) begin
    imm = 32'b0;  // [FIX Bug9] 默认赋值，防止综合推断 latch
    case (d_instr[6:0])
      7'b0010011, 7'b0000011, 7'b1100111: imm = {{20{d_instr[31]}}, d_instr[31:20]};  // I-type
      7'b0100011: imm = {{20{d_instr[31]}}, d_instr[31:25], d_instr[11:7]};  // S-type
      7'b1100011:
      imm = {
        {20{d_instr[31]}}, d_instr[31], d_instr[7], d_instr[30:25], d_instr[11:8], 1'b0
      };  // B-type
      7'b0110111, 7'b0010111: imm = {d_instr[31:12], 12'b0};  // U-type
      7'b1101111:
      imm = {{12{d_instr[31]}}, d_instr[19:12], d_instr[20], d_instr[30:21], 1'b0};  // J-type
      default: imm = 32'b0; 
    endcase
  end

endmodule
