`include "../include/defines.vh"
module ctrl (
    input  wire [31:0] instr,
    output reg         reg_we,     // 寄存器写使能
    output reg         mem_we,     // DMEM 写使能（Store）
    output reg         mem_re,     // DMEM 读使能（Load）
    output reg         branch,     // 条件分支标志
    output reg         jump,       // 无条件跳转（JAL/JALR）
    output reg         alu_src,    // ALU B 来源：0=rs2，1=imm
    output reg  [1:0]  wb_sel,     // 写回来源
    output reg  [3:0]  alu_op,     // ALU 操作码
    output reg  [1:0]  mem_width,  // 访存宽度
    output reg         mem_sign    // Load 符号扩展
);
    wire [6:0] opcode  = instr[6:0];
    wire [2:0] funct3  = instr[14:12];
    wire       f7b5    = instr[30];  // funct7[5]，区分 ADD/SUB，SRL/SRA

    always @(*) begin
        // ── 默认值（防止 latch）──────────────
        reg_we    = 1'b0;    mem_we    = 1'b0;
        mem_re    = 1'b0;    branch    = 1'b0;
        jump      = 1'b0;    alu_src   = 1'b0;
        wb_sel    = `WB_ALU; alu_op    = `ALU_ADD;
        mem_width = `MEM_WORD; mem_sign = 1'b1;

        case (opcode)

        // ══ R 型 ══════════════════════════════
        7'b011_0011: begin
            reg_we = 1'b1;
            case (funct3)
                3'b000: alu_op = f7b5 ? `ALU_SUB  : `ALU_ADD;  // ADD/SUB
                3'b001: alu_op = `ALU_SLL;   // SLL
                3'b010: alu_op = `ALU_SLT;   // SLT
                3'b011: alu_op = `ALU_SLTU;  // SLTU
                3'b100: alu_op = `ALU_XOR;   // XOR
                3'b101: alu_op = f7b5 ? `ALU_SRA  : `ALU_SRL;  // SRL/SRA
                3'b110: alu_op = `ALU_OR;    // OR
                3'b111: alu_op = `ALU_AND;   // AND
                default: alu_op = `ALU_ADD;
            endcase
        end

        // ══ I 型（立即数 ALU）════════════════
        7'b001_0011: begin
            reg_we = 1'b1;  alu_src = 1'b1;
            case (funct3)
                3'b000: alu_op = `ALU_ADD;   // ADDI
                3'b010: alu_op = `ALU_SLT;   // SLTI
                3'b011: alu_op = `ALU_SLTU;  // SLTIU
                3'b100: alu_op = `ALU_XOR;   // XORI
                3'b110: alu_op = `ALU_OR;    // ORI
                3'b111: alu_op = `ALU_AND;   // ANDI
                3'b001: alu_op = `ALU_SLL;   // SLLI
                3'b101: alu_op = f7b5 ? `ALU_SRA : `ALU_SRL; // SRLI/SRAI
                default: alu_op = `ALU_ADD;
            endcase
        end

        // ══ Load ═════════════════════════════
        7'b000_0011: begin
            reg_we = 1'b1;  mem_re = 1'b1;
            alu_src = 1'b1; wb_sel = `WB_MEM;
            case (funct3)
                3'b000: begin mem_width=`MEM_BYTE; mem_sign=1'b1; end // LB
                3'b001: begin mem_width=`MEM_HALF; mem_sign=1'b1; end // LH
                3'b010: begin mem_width=`MEM_WORD; mem_sign=1'b1; end // LW
                3'b100: begin mem_width=`MEM_BYTE; mem_sign=1'b0; end // LBU
                3'b101: begin mem_width=`MEM_HALF; mem_sign=1'b0; end // LHU
                default: mem_width = `MEM_WORD;
            endcase
        end

        // ══ Store ════════════════════════════
        7'b010_0011: begin
            mem_we = 1'b1;  alu_src = 1'b1;
            case (funct3)
                3'b000: mem_width = `MEM_BYTE;  // SB
                3'b001: mem_width = `MEM_HALF;  // SH
                3'b010: mem_width = `MEM_WORD;  // SW
                default: mem_width = `MEM_WORD;
            endcase
        end

        // ══ Branch ═══════════════════════════
        // ALU 计算分支目标地址 = pc + imm（alu_a=pc 在顶层处理）
        7'b110_0011: begin
            branch  = 1'b1;
            alu_src = 1'b1;   // alu_b = imm
            alu_op  = `ALU_ADD;
        end

        // ══ JAL ══════════════════════════════
        7'b110_1111: begin
            reg_we  = 1'b1;   jump    = 1'b1;
            alu_src = 1'b1;   wb_sel  = `WB_PC4;
            alu_op  = `ALU_ADD; // 目标 = pc + imm（alu_a=pc 在顶层处理）
        end

        // ══ JALR ═════════════════════════════
        7'b110_0111: begin
            reg_we  = 1'b1;   jump    = 1'b1;
            alu_src = 1'b1;   wb_sel  = `WB_PC4;
            alu_op  = `ALU_ADD; // 目标 = rs1 + imm（bit0 在顶层清零）
        end

        // ══ LUI ══════════════════════════════
        7'b011_0111: begin
            reg_we  = 1'b1;   alu_src = 1'b1;
            alu_op  = `ALU_LUI;
        end

        // ══ AUIPC ════════════════════════════
        7'b001_0111: begin
            reg_we  = 1'b1;   alu_src = 1'b1;
            alu_op  = `ALU_AUIPC; // alu_a=pc 在顶层处理
        end

        default: ; // NOP / 未定义：保持默认
        endcase
    end

endmodule