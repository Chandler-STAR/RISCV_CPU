module branch_comp (
    input [31:0] rs1_bc,
    input [31:0] rs2_bc,
    input [2:0] funct3_d,
    output reg branch_taken
);

  always @(*) begin
    case (funct3_d)
      3'b000:  branch_taken = (rs1_bc == rs2_bc);  // BEQ
      3'b001:  branch_taken = (rs1_bc != rs2_bc);  // BNE
      3'b100:  branch_taken = ($signed(rs1_bc) < $signed(rs2_bc));  // BLT
      3'b101:  branch_taken = ($signed(rs1_bc) >= $signed(rs2_bc));  // BGE
      3'b110:  branch_taken = (rs1_bc < rs2_bc);  // BLTU
      3'b111:  branch_taken = (rs1_bc >= rs2_bc);  // BGEU
      default: branch_taken = 1'b0;
    endcase
  end

endmodule
