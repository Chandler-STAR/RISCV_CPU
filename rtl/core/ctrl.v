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
    output reg  [ 4:0] alu_op_d,     // ALU 操作码
    output reg  [ 1:0] mem_width_d,  // 访存宽度
    output reg         mem_sign_d,   // Load 符号扩展
    output reg  [ 1:0] instr_type    // 指令类型：00=Branch, 01=Jump, 10=Call, 11=Ret

    // === Zicsr / Trap / M / B 扩展新增端口 ===
    output reg         is_csr_d,     // 当前是 zicsr 指令
    output reg  [ 1:0] csr_op_d,     // CSR_OP_RW/RS/RC
    output reg         csr_uimm_d,   // 1 = 立即数版本（rs1 字段当作 5 位零扩展立即数）
    output reg         is_ecall_d,   // 当前是 ecall
    output reg         is_mret_d,    // 当前是 mret
    output reg         is_mul_d,     // 当前是 M 扩展的 mul* 类
    output reg         is_div_d,     // 当前是 M 扩展的 div*/rem* 类
    output reg         is_bext_d     // 现场添加的 B 扩展指令命中
);

  localparam TYPE_BRANCH = 2'b00;
  localparam TYPE_JUMP = 2'b01;
  localparam TYPE_CALL = 2'b10;
  localparam TYPE_RET = 2'b11;

  wire [6:0] opcode = d_instr[6:0];
  wire [2:0] funct3 = d_instr[14:12];
  wire [6:0] funct7 = d_instr[31:25];//添加func7
  wire       f7b5 = d_instr[30];  // funct7[5]，区分 ADD/SUB，SRL/SRA

  wire [4:0] rd = d_instr[11:7];
  wire [4:0] rs1 = d_instr[19:15];

  // 辅助信号：判断是否是链接寄存器 (x1 或 x5)
  wire       rd_is_link = (rd == 5'd1 || rd == 5'd5);
  wire       rs1_is_link = (rs1 == 5'd1 || rs1 == 5'd5);

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
    instr_type = TYPE_BRANCH;  // 默认类型为分支，后续根据指令覆盖
    //给新增的控制信号赋默认值
    is_csr_d   = 1'b0;
    csr_op_d   = `CSR_OP_NONE;
    csr_uimm_d = 1'b0;
    is_ecall_d = 1'b0;
    is_mret_d  = 1'b0;
    is_mul_d   = 1'b0;
    is_div_d   = 1'b0;
    is_bext_d  = 1'b0;

    case (opcode)

      // ══ R 型 ══════════════════════════════
      7'b011_0011: begin
        reg_we_d = 1'b1;
        rs1_en_d = 1'b1;
        rs2_en_d = 1'b1;
        if(funct7 ==  7'b0000001) begin
          // ---- M 扩展 ----
          case (funct3)
            3'b000: begin alu_op_d = `ALU_MUL;    is_mul_d = 1'b1; end
            3'b001: begin alu_op_d = `ALU_MULH;   is_mul_d = 1'b1; end
            3'b010: begin alu_op_d = `ALU_MULHSU; is_mul_d = 1'b1; end
            3'b011: begin alu_op_d = `ALU_MULHU;  is_mul_d = 1'b1; end
            3'b100: begin alu_op_d = `ALU_DIV;    is_div_d = 1'b1; end
            3'b101: begin alu_op_d = `ALU_DIVU;   is_div_d = 1'b1; end
            3'b110: begin alu_op_d = `ALU_REM;    is_div_d = 1'b1; end
            3'b111: begin alu_op_d = `ALU_REMU;   is_div_d = 1'b1; end
          endcase
        end else begin
          // ---- 原 RV32I R 型译码 ----
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
        rs2_en_d  = 1'b1;
        rs1_en_d  = 1'b1;
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
        rs2_en_d  = 1'b1;
        rs1_en_d  = 1'b1;
        alu_src_d = 1'b1;  // alu_b = imm
        alu_op_d  = `ALU_ADD;
      end

      // ══ JAL ══════════════════════════════
      7'b110_1111: begin
        reg_we_d   = 1'b1;
        jump_d     = 1'b1;
        alu_src_d  = 1'b1;
        wb_sel_d   = `WB_PC4;
        alu_op_d   = `ALU_ADD;  // 目标 = pc + imm（alu_a=pc 在顶层处理）
        instr_type = rd_is_link ? TYPE_CALL : TYPE_JUMP;
      end

      // ══ JALR ═════════════════════════════
      7'b110_0111: begin
        reg_we_d = 1'b1;
        jump_d = 1'b1;
        rs1_en_d = 1'b1;
        alu_src_d = 1'b1;
        wb_sel_d = `WB_PC4;
        alu_op_d = `ALU_ADD;  // 目标 = rs1 + imm（bit0 在顶层清零）
        if (rd_is_link) begin
          // 情况 1: jalr x1, rs1, 0 -> 这是一个 Call
          instr_type = TYPE_CALL;
        end else if (rs1_is_link && rd == 5'd0) begin
          // 情况 2: jalr x0, x1, 0 -> 这是一个 Return (ret)
          instr_type = TYPE_RET;
        end else begin
          // 情况 3: 普通的间接跳转
          instr_type = TYPE_JUMP;
        end
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

      // ══ SYSTEM (Zicsr / ECALL / MRET) ════
      7'b111_0011: begin
        case (funct3)
          3'b000: begin
            // funct12 = instr[31:20]
            if (d_instr[31:20] == 12'h000)
              is_ecall_d = 1'b1;     // ECALL
            else if (d_instr[31:20] == 12'h302)
              is_mret_d = 1'b1;      // MRET
          end
          3'b001, 3'b010, 3'b011,        // csrrw / csrrs / csrrc
          3'b101, 3'b110, 3'b111: begin  // csrrwi / csrrsi / csrrci
            reg_we_d   = 1'b1;
            is_csr_d   = 1'b1;
            alu_op_d   = `ALU_CSR;
            alu_src_d  = 1'b1;            // ALU B 走 csr 通路（在顶层 mux）
            wb_sel_d   = `WB_ALU;         // 旧值通过 ALU 通道写回
            csr_uimm_d = funct3[2];       // 100/101/110/111 → uimm
            case (funct3[1:0])
              2'b01: csr_op_d = `CSR_OP_RW;
              2'b10: csr_op_d = `CSR_OP_RS;
              2'b11: csr_op_d = `CSR_OP_RC;
              default: csr_op_d = `CSR_OP_NONE;
            endcase
            // 非立即数版本需要 rs1
            rs1_en_d = ~funct3[2];
          end
          default: ;
        endcase
      end

      // ══ B 扩展现场槽位（保留模板，比赛当天补充编码）═══
      // 模板：
      // if (opcode == 7'bxxxxxxx && funct3 == 3'bxxx && funct7 == 7'bxxxxxxx) begin
      //     reg_we_d = 1'b1; rs1_en_d = 1'b1; rs2_en_d = 1'b1;
      //     alu_op_d = `ALU_BEXT0;
      //     is_bext_d = 1'b1;
      // end

      default: ;  // NOP / 未定义：保持默认
    endcase
  end

endmodule
