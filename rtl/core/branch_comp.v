module branch_comp (
    input [31:0] rs1_bc,
    input [31:0] rs2_bc,
    input [2:0] funct3_d,
    input wire predict_taken_in,  // 来自分支预测器的预测结果
    input wire e_branch,
    output reg branch_taken,
    output wire predict_direction_wrong  // 预测是否正确的信号，供分支预测器更新使用
);

  assign predict_direction_wrong = e_branch && (branch_taken != predict_taken_in);  // 预测错误时为1，正确时为0
  always @(*) begin
    if (e_branch)
      case (funct3_d)
        3'b000:  branch_taken = (rs1_bc == rs2_bc);  // BEQ
        3'b001:  branch_taken = (rs1_bc != rs2_bc);  // BNE
        3'b100:  branch_taken = ($signed(rs1_bc) < $signed(rs2_bc));  // BLT
        3'b101:  branch_taken = ($signed(rs1_bc) >= $signed(rs2_bc));  // BGE
        3'b110:  branch_taken = (rs1_bc < rs2_bc);  // BLTU
        3'b111:  branch_taken = (rs1_bc >= rs2_bc);  // BGEU
        default: branch_taken = 1'b0;
      endcase
    else branch_taken = 1'b0;  // 非分支指令不跳转
  end

endmodule
