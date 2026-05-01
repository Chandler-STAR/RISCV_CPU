#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
读取 branch_test.coe，生成带 PC 地址和汇编代码注释的 TXT 文件
格式：  <hex机器码>    // PC=0x????  <汇编助记符>
"""

# ============================================================
# 指令反汇编器（RV32I + 少量伪指令识别）
# ============================================================

REGS = [
    'zero','ra','sp','gp','tp',
    't0','t1','t2',
    's0','s1',
    'a0','a1','a2','a3','a4','a5','a6','a7',
    's2','s3','s4','s5','s6','s7','s8','s9','s10','s11',
    't3','t4','t5','t6'
]

def sign_ext(val, bits):
    if val & (1 << (bits - 1)):
        val -= (1 << bits)
    return val

def disasm(instr, pc):
    opcode  = instr & 0x7F
    rd      = (instr >> 7)  & 0x1F
    funct3  = (instr >> 12) & 0x7
    rs1     = (instr >> 15) & 0x1F
    rs2     = (instr >> 20) & 0x1F
    funct7  = (instr >> 25) & 0x7F

    # I-type imm
    imm_i = sign_ext((instr >> 20) & 0xFFF, 12)
    # S-type imm
    imm_s = sign_ext(((instr >> 25) & 0x7F) << 5 | ((instr >> 7) & 0x1F), 12)
    # B-type imm
    b12   = (instr >> 31) & 1
    b11   = (instr >> 7)  & 1
    b10_5 = (instr >> 25) & 0x3F
    b4_1  = (instr >> 8)  & 0xF
    imm_b = sign_ext((b12<<12)|(b11<<11)|(b10_5<<5)|(b4_1<<1), 13)
    # U-type imm
    imm_u = (instr >> 12) & 0xFFFFF
    # J-type imm
    j20    = (instr >> 31) & 1
    j19_12 = (instr >> 12) & 0xFF
    j11    = (instr >> 20) & 1
    j10_1  = (instr >> 21) & 0x3FF
    imm_j  = sign_ext((j20<<20)|(j19_12<<12)|(j11<<11)|(j10_1<<1), 21)

    rn = REGS  # shorthand

    # ── NOP ──────────────────────────────────────────────────
    if instr == 0x00000013:
        return "nop"

    # ── LUI ──────────────────────────────────────────────────
    if opcode == 0x37:
        return f"lui {rn[rd]}, 0x{imm_u:05x}"

    # ── AUIPC ─────────────────────────────────────────────────
    if opcode == 0x17:
        target = pc + (imm_u << 12)
        return f"auipc {rn[rd]}, 0x{imm_u:05x}  // -> 0x{target & 0xFFFFFFFF:08x}"

    # ── JAL ───────────────────────────────────────────────────
    if opcode == 0x6F:
        target = (pc + imm_j) & 0xFFFFFFFF
        if rd == 0:
            if imm_j == 0:
                return f"j . (finish, infinite loop)  // -> 0x{target:08x}"
            return f"j 0x{target:08x}  // offset={imm_j:+d}"
        return f"jal {rn[rd]}, 0x{target:08x}  // offset={imm_j:+d}"

    # ── JALR ──────────────────────────────────────────────────
    if opcode == 0x67 and funct3 == 0:
        if rd == 0 and rs1 == 1 and imm_i == 0:
            return "ret"
        if imm_i == 0:
            return f"jalr {rn[rd]}, {rn[rs1]}, 0"
        return f"jalr {rn[rd]}, {rn[rs1]}, {imm_i}"

    # ── BRANCH ────────────────────────────────────────────────
    if opcode == 0x63:
        target = (pc + imm_b) & 0xFFFFFFFF
        mne = {0:'beq', 1:'bne', 4:'blt', 5:'bge', 6:'bltu', 7:'bgeu'}.get(funct3, f'b?{funct3}')
        # 伪指令识别
        if rs2 == 0:
            pmne = {'beq':'beqz','bne':'bnez','blt':'bltz','bge':'bgez'}.get(mne)
            if pmne:
                return f"{pmne} {rn[rs1]}, 0x{target:08x}  // offset={imm_b:+d}"
        if rs1 == 0:
            pmne = {'blt':'bgtz','bge':'blez'}.get(mne)
            if pmne:
                return f"{pmne} {rn[rs2]}, 0x{target:08x}  // offset={imm_b:+d}"
        return f"{mne} {rn[rs1]}, {rn[rs2]}, 0x{target:08x}  // offset={imm_b:+d}"

    # ── LOAD ──────────────────────────────────────────────────
    if opcode == 0x03:
        mne = {0:'lb', 1:'lh', 2:'lw', 4:'lbu', 5:'lhu'}.get(funct3, f'l?{funct3}')
        return f"{mne} {rn[rd]}, {imm_i}({rn[rs1]})"

    # ── STORE ─────────────────────────────────────────────────
    if opcode == 0x23:
        mne = {0:'sb', 1:'sh', 2:'sw'}.get(funct3, f's?{funct3}')
        return f"{mne} {rn[rs2]}, {imm_s}({rn[rs1]})"

    # ── OP-IMM ────────────────────────────────────────────────
    if opcode == 0x13:
        if funct3 == 0:  # addi
            if rs1 == 0:
                return f"li {rn[rd]}, {imm_i}"
            if imm_i == 0:
                return f"mv {rn[rd]}, {rn[rs1]}"
            return f"addi {rn[rd]}, {rn[rs1]}, {imm_i}"
        if funct3 == 1:  # slli
            shamt = imm_i & 0x1F
            return f"slli {rn[rd]}, {rn[rs1]}, {shamt}"
        if funct3 == 2:  return f"slti  {rn[rd]}, {rn[rs1]}, {imm_i}"
        if funct3 == 3:  return f"sltiu {rn[rd]}, {rn[rs1]}, {imm_i}"
        if funct3 == 4:  return f"xori  {rn[rd]}, {rn[rs1]}, {imm_i}"
        if funct3 == 5:
            shamt = imm_i & 0x1F
            if (imm_i >> 5) & 0x7F == 0x20:
                return f"srai {rn[rd]}, {rn[rs1]}, {shamt}"
            return f"srli {rn[rd]}, {rn[rs1]}, {shamt}"
        if funct3 == 6:  return f"ori  {rn[rd]}, {rn[rs1]}, {imm_i}"
        if funct3 == 7:
            if imm_i == 1:
                return f"andi {rn[rd]}, {rn[rs1]}, 1"
            return f"andi {rn[rd]}, {rn[rs1]}, {imm_i}"

    # ── OP (R-type) ───────────────────────────────────────────
    if opcode == 0x33:
        if funct7 == 0x01:  # RV32M
            mne = {0:'mul',1:'mulh',2:'mulhsu',3:'mulhu',
                   4:'div',5:'divu',6:'rem',7:'remu'}.get(funct3, f'm?{funct3}')
            return f"{mne} {rn[rd]}, {rn[rs1]}, {rn[rs2]}"
        mne_map = {
            (0,0x00):'add', (0,0x20):'sub',
            (1,0x00):'sll', (2,0x00):'slt', (3,0x00):'sltu',
            (4,0x00):'xor', (5,0x00):'srl', (5,0x20):'sra',
            (6,0x00):'or',  (7,0x00):'and',
        }
        mne = mne_map.get((funct3, funct7), f'r?f3={funct3},f7={funct7}')
        return f"{mne} {rn[rd]}, {rn[rs1]}, {rn[rs2]}"

    # ── FENCE / ECALL / EBREAK ────────────────────────────────
    if opcode == 0x0F: return "fence"
    if opcode == 0x73:
        if instr == 0x00000073: return "ecall"
        if instr == 0x00100073: return "ebreak"
        return f"csr? 0x{instr:08x}"

    return f"unknown 0x{instr:08x}"


# ============================================================
# 读取 COE 文件，解析机器码列表
# ============================================================
coe_path = r"e:\FPGA\github\RISCV\RISCV_CPU\tests\my_test_data\branch_test.coe"
out_path = r"e:\FPGA\github\RISCV\RISCV_CPU\tests\my_test_data\branch_test_annotated.txt"

instrs = []
with open(coe_path, "r", encoding="utf-8") as f:
    in_vector = False
    for line in f:
        line = line.strip()
        if line.startswith("memory_initialization_vector"):
            in_vector = True
            continue
        if not in_vector:
            continue
        # 去掉注释、逗号、分号
        line = line.split(";")[0].split(",")[0].strip()
        if line:
            instrs.append(int(line, 16))

# ============================================================
# 生成注释文件
# ============================================================
lines = []
lines.append(f"// branch_test_annotated.txt")
lines.append(f"// RV32I Branch Prediction Test")
lines.append(f"// Format: <hex>    // PC=0x????  <disassembly>")
lines.append(f"// Total: {len(instrs)} instructions ({len(instrs)*4} bytes)")
lines.append("")

for i, enc in enumerate(instrs):
    pc = i * 4
    asm = disasm(enc, pc)
    lines.append(f"{enc:08x}    // PC=0x{pc:04X}  {asm}")

content = "\n".join(lines)
with open(out_path, "w", encoding="utf-8") as f:
    f.write(content)

print(content)
print(f"\n已生成: {out_path}")
