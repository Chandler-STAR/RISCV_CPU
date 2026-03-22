`include "defines.vh"

module ctrl (
    input [31:0] d_instr,

    output reg reg_we_d,

    output reg mem_we_d,
    output reg mem_re_d,
    //条件分支标志（B-type=1）
    output reg branch_d,
    //无条件跳转（JAL/JALR=1）
    output reg jump_d,
    //ALU B 来源：0=rs2（R型），1=imm（I/S/B/U/J型）
    output reg alu_src_d,
    //寄存器写回选择：WB_ALU=00 / WB_MEM=01 / WB_PC4=10
    output reg [1:0] wb_sel_d,
    //ALU操作码
    output reg [3:0] alu_op_d,
    //内存访问宽度：MEM_BYTE=00 / MEM_HALF=01 / MEM_WORD=10
    output reg [1:0] mem_width_d,
    //load符号扩展：0=无符号，1=有符号
    output reg mem_sign_d
);

  wire [6:0] opcode = d_instr[6:0];
  wire [2:0] funct3 = d_instr[14:12];
  wire [6:0] funct7 = d_instr[31:25];



  always @(*) begin
    //initialize

    reg_we_d = 0;
    mem_we_d = 0;
    mem_re_d = 0;
    branch_d = 0;
    jump_d = 0;
    alu_src_d = 0;
    wb_sel_d = 2'b0;
    alu_op_d = 4'b0;
    mem_width_d = 2'b0;
    mem_sign_d = 1;


    case (opcode)
      0110011: begin  // R-type ALU
        reg_we_d  = 1;
        alu_src_d = 0;
        wb_sel_d  = `WB_ALU;
      end
      0010011: begin  // I-type ALU
        reg_we_d  = 1;
        alu_src_d = 1;
        wb_sel_d  = `WB_ALU;
      end
      0000011: begin  // Load
        reg_we_d  = 1;
        mem_re_d  = 1;
        alu_src_d = 1;
        wb_sel_d  = `WB_MEM;
        case (funct3)
          3'b000:  mem_width_d = `MEM_BYTE;  // LB
          3'b001:  mem_width_d = `MEM_HALF;  // LH
          3'b010:  mem_width_d = `MEM_WORD;  // LW
          3'b100: begin
            mem_width_d = `MEM_BYTE;
            mem_sign_d  = 0;
          end  // LBU
          3'b101: begin
            mem_width_d = `MEM_HALF;
            mem_sign_d  = 0;
          end  // LHU
          default: ;
        endcase
      end
      0100011: begin  // Store
        mem_we_d  = 1;
        alu_src_d = 1;
        case (funct3)
          3'b000:  mem_width_d = `MEM_BYTE;  // SB
          3'b001:  mem_width_d = `MEM_HALF;  // SH
          3'b010:  mem_width_d = `MEM_WORD;  // SW
          default: ;
        endcase
      end
      1100011: begin  // Branch
        branch_d  = 1;
        alu_src_d = 0;
      end
      1101111, 1100111: begin  // JAL JALR
        reg_we_d  = 1;
        jump_d    = 1;
        alu_src_d = 1;
        wb_sel_d  = `WB_PC4;
      end
      0110111, 0010111: begin  // LUI AUIPC
        reg_we_d  = 1;
        alu_src_d = 1;
        wb_sel_d  = `WB_ALU;
      end
      default: ;
    endcase
  end
endmodule
