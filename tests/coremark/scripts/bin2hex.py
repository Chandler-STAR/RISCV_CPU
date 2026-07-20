#!/usr/bin/env python3
"""
把二进制文件（.bin）转换成 Verilog 仿真 $readmemh 能直接读取的十六进制文件（.hex）
按 32 位 小端序 解析
格式：每行1个32位数据，对应内存地址从0开始递增
"""

#导入依赖库
import sys
import struct

if len(sys.argv) != 3:
    print("Usage: bin2hex.py <input.bin> <output.hex>", file=sys.stderr)
    sys.exit(1)

src, dst = sys.argv[1], sys.argv[2]
with open(src, "rb") as f:
    data = f.read()

# 4 字节对齐
pad = (-len(data)) % 4
if pad:
    data += b"\x00" * pad

with open(dst, "w") as f:
    for i in range(0, len(data), 4):
        word = struct.unpack("<I", data[i:i + 4])[0]
        f.write(f"{word:08x}\n")

# 输出转换结果和统计信息
words = len(data) // 4
print(f"[bin2hex] {src} ({len(data)} B) -> {dst} ({words} words)")
