`include "../include/defines.vh"
module ctrl (
    input  wire [31:0] d_instr,
    output reg         reg_we_d,     // 寄存器写使能
    output reg         mem_we_d,     // DMEM 写使能（Store）
    output reg         mem_re_d,     // DMEM 读使能（Load）
    output reg         branch_d,     // 条件分支标志
    output reg         jump_d,       // 无条件跳转（JAL/JALR）
    output reg         alu_src_d,    // ALU B 来源：0=rs2，1=imm
    output reg         rs1_en_d,     // ID指令是否使用rs1（排除LUI/AUIPC/JAL）
    output reg         rs2_en_d,     // ID指令是否使用rs2（排除I-type/Load等）
    output reg  [ 1:0] wb_sel_d,     // 写回来源
    output reg  [ 3:0] alu_op_d,     // ALU 操作码
    output reg  [ 1:0] mem_width_d,  // 访存宽度
    output reg         mem_sign_d    // Load 符号扩展
);
  wire [6:0] opcode = d_instr[6:0];
  wire [2:0] funct3 = d_instr[14:12];
  wire       f7b5 = d_instr[30];  // funct7[5]，区分 ADD/SUB，SRL/SRA

  always @(*) begin
    // ── 默认值（防止 latch）──────────────
    reg_we_d  = 1'b0;
    mem_we_d  = 1'b0;
    mem_re_d  = 1'b0;
    branch_d  = 1'b0;
    jump_d    = 1'b0;
    alu_src_d   = 1'b0;
    rs2_en_d    = 1'b0;
    rs1_en_d    = 1'b0;
    wb_sel_d    = `WB_ALU;
    alu_op_d    = `ALU_ADD;
    mem_width_d = `MEM_WORD;
    mem_sign_d  = 1'b1;

    case (opcode)

      // ══ R 型 ══════════════════════════════
      7'b011_0011: begin
        reg_we_d = 1'b1;
        rs1_en_d = 1'b1;
        rs2_en_d = 1'b1;
        case (funct3)
          3'b000:  alu_op_d = f7b5 ? `ALU_SUB : `ALU_ADD;  // ADD/SUB
          3'b001:  alu_op_d = `ALU_SLL;  // SLL
          3'b010:  alu_op_d = `ALU_SLT;  // SLT
          3'b011:  alu_op_d = `ALU_SLTU;  // SLTU
          3'b100:  alu_op_d = `ALU_XOR;  // XOR
          3'b101:  alu_op_d = f7b5 ? `ALU_SRA : `ALU_SRL;  // SRL/SRA
          3'b110:  alu_op_d = `ALU_OR;  // OR
          3'b111:  alu_op_d = `ALU_AND;  // AND
          default: alu_op_d = `ALU_ADD;
        endcase
      end

      // ══ I 型（立即数 ALU）════════════════
      7'b001_0011: begin
        reg_we_d  = 1'b1;
        alu_src_d = 1'b1;
        rs1_en_d  = 1'b1;
        case (funct3)
          3'b000:  alu_op_d = `ALU_ADD;  // ADDI
          3'b010:  alu_op_d = `ALU_SLT;  // SLTI
          3'b011:  alu_op_d = `ALU_SLTU;  // SLTIU
          3'b100:  alu_op_d = `ALU_XOR;  // XORI
          3'b110:  alu_op_d = `ALU_OR;  // ORI
          3'b111:  alu_op_d = `ALU_AND;  // ANDI
          3'b001:  alu_op_d = `ALU_SLL;  // SLLI
          3'b101:  alu_op_d = f7b5 ? `ALU_SRA : `ALU_SRL;  // SRLI/SRAI
          default: alu_op_d = `ALU_ADD;
        endcase
      end

      // ══ Load ═════════════════════════════
      7'b000_0011: begin
        reg_we_d  = 1'b1;
        mem_re_d  = 1'b1;
        alu_src_d = 1'b1;
        rs1_en_d  = 1'b1;
        wb_sel_d  = `WB_MEM;
        case (funct3)
          3'b000: begin
            mem_width_d = `MEM_BYTE;
            mem_sign_d  = 1'b1;
          end  // LB
          3'b001: begin
            mem_width_d = `MEM_HALF;
            mem_sign_d  = 1'b1;
          end  // LH
          3'b010: begin
            mem_width_d = `MEM_WORD;
            mem_sign_d  = 1'b1;
          end  // LW
          3'b100: begin
            mem_width_d = `MEM_BYTE;
            mem_sign_d  = 1'b0;
          end  // LBU
          3'b101: begin
            mem_width_d = `MEM_HALF;
            mem_sign_d  = 1'b0;
          end  // LHU
          default: mem_width_d = `MEM_WORD;
        endcase
      end

      // ══ Store ════════════════════════════
      7'b010_0011: begin
        mem_we_d  = 1'b1;
        rs2_en_d = 1'b1;
        rs1_en_d = 1'b1;
        alu_src_d = 1'b1;
        case (funct3)
          3'b000:  mem_width_d = `MEM_BYTE;  // SB
          3'b001:  mem_width_d = `MEM_HALF;  // SH
          3'b010:  mem_width_d = `MEM_WORD;  // SW
          default: mem_width_d = `MEM_WORD;
        endcase
      end

      // ══ Branch ═══════════════════════════
      // ALU 计算分支目标地址 = pc + imm（alu_a=pc 在顶层处理）
      7'b110_0011: begin
        branch_d  = 1'b1;
        rs2_en_d = 1'b1;
        rs1_en_d = 1'b1;
        alu_src_d = 1'b1;  // alu_b = imm
        alu_op_d  = `ALU_ADD;
      end

      // ══ JAL ══════════════════════════════
      7'b110_1111: begin
        reg_we_d = 1'b1;
        jump_d = 1'b1;
        alu_src_d = 1'b1;
        wb_sel_d = `WB_PC4;
        alu_op_d = `ALU_ADD;  // 目标 = pc + imm（alu_a=pc 在顶层处理）
      end

      // ══ JALR ═════════════════════════════
      7'b110_0111: begin
        reg_we_d = 1'b1;
        jump_d = 1'b1;
        rs1_en_d = 1'b1;
        alu_src_d = 1'b1;
        wb_sel_d = `WB_PC4;
        alu_op_d = `ALU_ADD;  // 目标 = rs1 + imm（bit0 在顶层清零）
      end

      // ══ LUI ══════════════════════════════
      7'b011_0111: begin
        reg_we_d  = 1'b1;
        alu_src_d = 1'b1;
        alu_op_d  = `ALU_LUI;
      end

      // ══ AUIPC ════════════════════════════
      7'b001_0111: begin
        reg_we_d  = 1'b1;
        alu_src_d = 1'b1;
        alu_op_d  = `ALU_AUIPC;  // alu_a=pc 在顶层处理
      end

      default: ;  // NOP / 未定义：保持默认
    endcase
  end

endmodule
