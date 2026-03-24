module dmem (
    input clk,
    input [31:0] alu_out,
    input [31:0] rs2,
    input mem_we,
    input mem_re,
    input [1:0] mem_width,
    input mem_sign,
    output reg [31:0] dmem_rdata
);

  reg [31:0] dmem[0:1023];

  always @(posedge clk) begin
    if (mem_we) begin
      case (mem_width)
        2'b00:   dmem[alu_out[11:2]] <= {24'b0, rs2[7:0]};  // SB
        2'b01:   dmem[alu_out[11:2]] <= {16'b0, rs2[15:0]};  // SH
        2'b10:   dmem[alu_out[11:2]] <= rs2;  // SW
        default: ;
      endcase
    end
  end


  always @(*) begin
    if (mem_re) begin
      case (mem_width)
        2'b00:
        dmem_rdata <= mem_sign ? {{24{dmem[alu_out[11:2]][7]}}, dmem[alu_out[11:2]][7:0]} : {24'b0, dmem[alu_out[11:2]][7:0]}; // LB/LBU
        2'b01:
        dmem_rdata <= mem_sign ? {{16{dmem[alu_out[11:2]][15]}}, dmem[alu_out[11:2]][15:0]} : {16'b0, dmem[alu_out[11:2]][15:0]}; // LH/LHU
        2'b10: dmem_rdata <= dmem[alu_out[11:2]];  // LW
        default: ;
      endcase
    end
  end
endmodule
