#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
手工汇编器：将新版 branch_test.s (纯 RV32I) 编译为机器码，输出 .coe 文件
程序从地址 0x00000000 开始

指令地址布局（第一遍扫描，确定所有标签地址）：

_start:
  0x00: addi t0, x0, 20          (1)
loop_simple:
  0x04: addi t0, t0, -1          (2)
  0x08: bne  t0, x0, loop_simple (3) offset = 0x04-0x08 = -4

  0x0C: addi t0, x0, 20          (4)
  0x10: addi t1, x0, 1           (5)
loop_parity:
  0x14: and  t2, t0, t1          (6)
  0x18: beq  t2, x0, is_even     (7) offset = is_even - 0x18
  # 奇数路径
  0x1C: addi x0, x0, 0  (nop)    (8)
  0x20: j next_parity            (9) jal x0, next_parity-0x20
is_even:
  0x24: addi x0, x0, 0  (nop)   (10)
next_parity:
  0x28: addi t0, t0, -1         (11)
  0x2C: bne  t0, x0, loop_parity (12) offset = 0x14-0x2C = -0x18

  0x30: addi t0, x0, 30         (13)
  0x34: addi t1, x0, 0          (14)
loop_pattern:
  0x38: addi t1, t1, 1          (15)
  0x3C: addi t2, x0, 3          (16)
  0x40: blt  t1, t2, is_taken   (17) offset = is_taken - 0x40
  # not taken path (t1>=3)
  0x44: addi t1, x0, 0          (18)
  0x48: j pattern_end           (19) jal x0, pattern_end-0x48
is_taken:
  0x4C: addi x0, x0, 0 (nop)   (20)
pattern_end:
  0x50: addi t0, t0, -1        (21)
  0x54: bne  t0, x0, loop_pattern (22) offset = 0x38-0x54 = -0x1C

  0x58: addi t0, x0, 20        (23)
  # lui t2, %hi(target_1) — target_1 地址待定
  # target_1 对齐到 .align 4，先计算主体结束位置再确定
  # 主体到 finish 结束后对齐:
  #   0x5C: lui t2, hi(target_1)   (24)
  #   0x60: addi t2, t2, lo(t1)   (25)
  #   0x64: lui t3, hi(target_2)   (26)
  #   0x68: addi t3, t3, lo(t2)   (27)
  # loop_btb:
  #   0x6C: andi t1, t0, 1         (28)
  #   0x70: beq  t1, x0, call_2    (29) offset = call_2-0x70
  #   0x74: jalr ra, t2, 0         (30)
  #   0x78: j btb_done             (31) jal x0, btb_done-0x78
  # call_2:
  #   0x7C: jalr ra, t3, 0         (32)
  # btb_done:
  #   0x80: addi t0, t0, -1        (33)
  #   0x84: bne  t0, x0, loop_btb  (34) offset = 0x6C-0x84 = -0x18
  # finish:
  #   0x88: j finish               (35) jal x0, 0
  #
  # .align 4 后 (0x88+4=0x8C 已经是4字节对齐)
  # target_1:    0x8C
  #   0x8C: addi a0, x0, 1         (36)
  #   0x90: jalr x0, ra, 0 (ret)   (37)
  # .align 4 后 (0x90+4=0x94 已经是4字节对齐)
  # target_2:    0x94
  #   0x94: addi a0, x0, 2         (38)
  #   0x98: jalr x0, ra, 0 (ret)   (39)
"""

# ============================================================
# 寄存器映射
# ============================================================
REGS = {
    'zero':0,'x0':0, 'ra':1,'x1':1, 'sp':2,'x2':2,
    'gp':3,'x3':3,   'tp':4,'x4':4,
    't0':5,'x5':5,   't1':6,'x6':6,  't2':7,'x7':7,
    's0':8,'fp':8,'x8':8, 's1':9,'x9':9,
    'a0':10,'x10':10,'a1':11,'x11':11,'a2':12,'x12':12,
    'a3':13,'x13':13,'a4':14,'x14':14,'a5':15,'x15':15,
    'a6':16,'x16':16,'a7':17,'x17':17,
    's2':18,'x18':18,'s3':19,'x19':19,'s4':20,'x20':20,
    's5':21,'x21':21,'s6':22,'x22':22,'s7':23,'x23':23,
    's8':24,'x24':24,'s9':25,'x25':25,
    's10':26,'x26':26,'s11':27,'x27':27,
    't3':28,'x28':28,'t4':29,'x29':29,'t5':30,'x30':30,'t6':31,'x31':31,
}

def R(reg): return REGS[reg]

def sign_ext(val, bits):
    if val & (1 << (bits - 1)):
        val -= (1 << bits)
    return val

# ============================================================
# 指令编码
# ============================================================

def enc_I(imm, rs1, funct3, rd, opcode):
    return ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def enc_R(funct7, rs2, rs1, funct3, rd, opcode):
    return ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | \
           ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
           ((rd & 0x1F) << 7) | (opcode & 0x7F)

def enc_B(imm, rs2, rs1, funct3, opcode):
    imm = imm & 0x1FFF
    b12   = (imm >> 12) & 1
    b11   = (imm >> 11) & 1
    b10_5 = (imm >> 5)  & 0x3F
    b4_1  = (imm >> 1)  & 0xF
    return (b12 << 31) | (b10_5 << 25) | ((rs2 & 0x1F) << 20) | \
           ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
           (b4_1 << 8) | (b11 << 7) | (opcode & 0x7F)

def enc_U(imm, rd, opcode):
    return ((imm & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def enc_J(imm, rd, opcode):
    imm = imm & 0x1FFFFF
    b20    = (imm >> 20) & 1
    b19_12 = (imm >> 12) & 0xFF
    b11    = (imm >> 11) & 1
    b10_1  = (imm >> 1)  & 0x3FF
    return (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | \
           ((rd & 0x1F) << 7) | (opcode & 0x7F)

# ============================================================
# 常用指令
# ============================================================
def NOP():    return enc_I(0, 0, 0, 0, 0x13)  # addi x0, x0, 0
def ADDI(rd, rs1, imm):  return enc_I(imm, R(rs1), 0, R(rd), 0x13)
def AND(rd, rs1, rs2):   return enc_R(0, R(rs2), R(rs1), 7, R(rd), 0x33)
def ANDI(rd, rs1, imm):  return enc_I(imm, R(rs1), 7, R(rd), 0x13)
def BEQ(rs1, rs2, imm):  return enc_B(imm, R(rs2), R(rs1), 0, 0x63)
def BNE(rs1, rs2, imm):  return enc_B(imm, R(rs2), R(rs1), 1, 0x63)
def BLT(rs1, rs2, imm):  return enc_B(imm, R(rs2), R(rs1), 4, 0x63)
def JAL(rd, imm):        return enc_J(imm, R(rd), 0x6F)
def JALR(rd, rs1, imm):  return enc_I(imm, R(rs1), 0, R(rd), 0x67)
def LUI(rd, imm20):      return enc_U(imm20, R(rd), 0x37)

def hi20(addr):
    """%hi(addr): 高20位，如 lo12 最高位为1则+1"""
    lo = addr & 0xFFF
    hi = (addr >> 12) & 0xFFFFF
    if lo & 0x800:
        hi = (hi + 1) & 0xFFFFF
    return hi

def lo12(addr):
    """%lo(addr): 符号扩展的低12位"""
    return sign_ext(addr & 0xFFF, 12) & 0xFFF

# ============================================================
# 地址常量（由上方布局注释推导）
# ============================================================
TARGET_1 = 0x8C
TARGET_2 = 0x94

# ============================================================
# 逐条编码（与 .s 文件一一对应）
# ============================================================
instrs = []   # list of (addr, encoding, comment)
pc = 0

def emit(enc, comment=""):
    global pc
    instrs.append((pc, enc, comment))
    pc += 4

# ── Section 1: 基础向后跳转 ──────────────────────────────────
emit(ADDI('t0','x0', 20),          "_start: addi t0, x0, 20")
# loop_simple: @ 0x04
LOOP_SIMPLE = pc
emit(ADDI('t0','t0', -1),          "loop_simple: addi t0, t0, -1")
emit(BNE('t0','x0', LOOP_SIMPLE - pc), "bne t0, x0, loop_simple")

# ── Section 2: 交替模式 ───────────────────────────────────────
emit(ADDI('t0','x0', 20),          "addi t0, x0, 20")
emit(ADDI('t1','x0', 1),           "addi t1, x0, 1")
# loop_parity: @ 0x14
LOOP_PARITY = pc
emit(AND('t2','t0','t1'),          "loop_parity: and t2, t0, t1")
# beq t2, x0, is_even  — is_even @ 0x24
IS_EVEN = pc + 4 + 4 + 4   # beq(0x18) + nop(0x1C) + j(0x20) → 0x24
emit(BEQ('t2','x0', IS_EVEN - pc), "beq t2, x0, is_even")
emit(NOP(),                        "nop (奇数路径)")
# j next_parity — next_parity @ 0x28  (is_even(0x24)+nop(0x24))
NEXT_PARITY = IS_EVEN + 4   # 0x28
emit(JAL('x0', NEXT_PARITY - pc),  "j next_parity")
# is_even: @ 0x24
assert pc == IS_EVEN, f"IS_EVEN mismatch: pc={pc:#x}, expected {IS_EVEN:#x}"
emit(NOP(),                        "is_even: nop (偶数路径)")
# next_parity: @ 0x28
assert pc == NEXT_PARITY, f"NEXT_PARITY mismatch: pc={pc:#x}"
emit(ADDI('t0','t0', -1),          "next_parity: addi t0, t0, -1")
emit(BNE('t0','x0', LOOP_PARITY - pc), "bne t0, x0, loop_parity")

# ── Section 3: TTN 周期模式 ───────────────────────────────────
emit(ADDI('t0','x0', 30),          "addi t0, x0, 30")
emit(ADDI('t1','x0', 0),           "addi t1, x0, 0")
# loop_pattern: @ 0x38
LOOP_PATTERN = pc
emit(ADDI('t1','t1', 1),           "loop_pattern: addi t1, t1, 1")
emit(ADDI('t2','x0', 3),           "addi t2, x0, 3")
# blt t1, t2, is_taken — is_taken @ 0x4C (blt+addi+j+is_taken)
IS_TAKEN = pc + 4 + 4 + 4   # blt(0x40)+addi(0x44)+j(0x48) → 0x4C
emit(BLT('t1','t2', IS_TAKEN - pc),"blt t1, t2, is_taken")
# not-taken path
emit(ADDI('t1','x0', 0),           "addi t1, x0, 0 (reset)")
# j pattern_end — pattern_end @ 0x50 (is_taken(0x4C)+nop(0x4C))
PATTERN_END = IS_TAKEN + 4   # 0x50
emit(JAL('x0', PATTERN_END - pc),  "j pattern_end")
# is_taken: @ 0x4C
assert pc == IS_TAKEN, f"IS_TAKEN mismatch: pc={pc:#x}, expected {IS_TAKEN:#x}"
emit(NOP(),                        "is_taken: nop")
# pattern_end: @ 0x50
assert pc == PATTERN_END, f"PATTERN_END mismatch: pc={pc:#x}"
emit(ADDI('t0','t0', -1),          "pattern_end: addi t0, t0, -1")
emit(BNE('t0','x0', LOOP_PATTERN - pc), "bne t0, x0, loop_pattern")

# ── Section 4: BTB 测试 ───────────────────────────────────────
emit(ADDI('t0','x0', 20),          "addi t0, x0, 20")
# lui t2, %hi(target_1)
emit(LUI('t2', hi20(TARGET_1)),    f"lui t2, %hi(target_1=0x{TARGET_1:x})")
# addi t2, t2, %lo(target_1)
emit(ADDI('t2','t2', lo12(TARGET_1)), f"addi t2, t2, %lo(target_1=0x{TARGET_1:x})")
# lui t3, %hi(target_2)
emit(LUI('t3', hi20(TARGET_2)),    f"lui t3, %hi(target_2=0x{TARGET_2:x})")
# addi t3, t3, %lo(target_2)
emit(ADDI('t3','t3', lo12(TARGET_2)), f"addi t3, t3, %lo(target_2=0x{TARGET_2:x})")

# loop_btb: @ 0x6C
LOOP_BTB = pc
emit(ANDI := ANDI if 'ANDI' in dir() else None, "")  # placeholder
instrs.pop()
pc -= 4

def ANDI(rd, rs1, imm): return enc_I(imm, R(rs1), 7, R(rd), 0x13)

emit(ANDI('t1','t0', 1),           "loop_btb: andi t1, t0, 1")
# beq t1, x0, call_2  — call_2 @ loop_btb+4+4+4+4 = LOOP_BTB+0x10
CALL_2 = LOOP_BTB + 4 + 4 + 4 + 4   # andi+beq+jalr+j → call_2
emit(BEQ('t1','x0', CALL_2 - pc),  "beq t1, x0, call_2")
emit(JALR('ra','t2', 0),           "jalr ra, t2, 0 (→target_1)")
# j btb_done — btb_done @ call_2+4
BTB_DONE = CALL_2 + 4
emit(JAL('x0', BTB_DONE - pc),     "j btb_done")
# call_2:
assert pc == CALL_2, f"CALL_2 mismatch: pc={pc:#x}, expected {CALL_2:#x}"
emit(JALR('ra','t3', 0),           "call_2: jalr ra, t3, 0 (→target_2)")
# btb_done:
assert pc == BTB_DONE, f"BTB_DONE mismatch: pc={pc:#x}"
emit(ADDI('t0','t0', -1),          "btb_done: addi t0, t0, -1")
emit(BNE('t0','x0', LOOP_BTB - pc),"bne t0, x0, loop_btb")

# ── Section 5: finish ─────────────────────────────────────────
FINISH = pc
emit(JAL('x0', 0),                 "finish: j finish (infinite loop)")

# ── .align 4 后的 target_1 ───────────────────────────────────
# finish 结束后地址，判断是否需要补齐
while pc % 4 != 0:
    emit(NOP(), "padding")
# target_1:
assert pc == TARGET_1, f"TARGET_1 mismatch: pc={pc:#x}, expected {TARGET_1:#x}"
emit(ADDI('a0','x0', 1),           "target_1: addi a0, x0, 1")
emit(JALR('x0','ra', 0),           "jalr x0, ra, 0 (ret)")

# ── .align 4 后的 target_2 ───────────────────────────────────
while pc % 4 != 0:
    emit(NOP(), "padding")
# target_2:
assert pc == TARGET_2, f"TARGET_2 mismatch: pc={pc:#x}, expected {TARGET_2:#x}"
emit(ADDI('a0','x0', 2),           "target_2: addi a0, x0, 2")
emit(JALR('x0','ra', 0),           "jalr x0, ra, 0 (ret)")

# ============================================================
# 打印汇编结果
# ============================================================
print("=== 指令编码结果 ===")
for addr, enc, comment in instrs:
    print(f"  {addr:04X}: {enc:08x}  # {comment}")

print(f"\n共 {len(instrs)} 条指令，{len(instrs)*4} 字节")
print(f"  target_1 @ 0x{TARGET_1:X}")
print(f"  target_2 @ 0x{TARGET_2:X}")
print(f"  finish   @ 0x{FINISH:X}")

# ============================================================
# 生成 .coe 文件
# ============================================================
coe_path = r"e:\FPGA\github\RISCV\RISCV_CPU\tests\my_test_data\branch_test.coe"
lines = [
    "; branch_test.coe",
    "; Auto-generated from branch_test.s (RV32I only)",
    "; Base address: 0x00000000",
    "memory_initialization_radix=16;",
    "memory_initialization_vector=",
]
for i, (_, enc, _) in enumerate(instrs):
    sep = "," if i < len(instrs) - 1 else ";"
    lines.append(f"{enc:08x}{sep}")
with open(coe_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
print(f"\n已生成 COE 文件: {coe_path}")

# 同时生成 .txt
txt_path = r"e:\FPGA\github\RISCV\RISCV_CPU\tests\my_test_data\branch_test.txt"
with open(txt_path, "w", encoding="utf-8") as f:
    for _, enc, _ in instrs:
        f.write(f"{enc:08x}\n")
print(f"已生成 TXT 文件: {txt_path}")
