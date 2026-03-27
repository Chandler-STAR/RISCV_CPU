# 日志

## 2026-3-18
更新了设计规范
编写define.vh全局 宏定义
增加微架构图片
更新设计规则

## 2026-3-21
初步编写riscv_top.v 未经过测试

## 2026-3-22
完成riscv_top.v顶层文件的编写，具体包括
* 导线定义规则
* 顶层组合逻辑
* 模块例化

初步编写branch_comp.v
### 后续优化：模块命名，pc4数据通路，可读性......

## 2026-3-23

### 对 riscv_top.v 顶层模块进行代码审查，整体逻辑正确，无明显连线错误。记录以下待确认事项：

* stall/flush 优先级：id_ex_reg 无 stall 端口，load-use 冒险处理依赖 hazard 同时拉高 stall 与 flush，且 if_id_reg 内部需优先响应 stall，待核查两模块实现。
* 分支前递覆盖范围：fwd_br_a/b 仅覆盖 MEM 级前递，EX 级结果无法直接前递给 branch_comp，需确认 hazard 模块已对此情况插入气泡。
* zero 信号未使用：ALU 输出 zero 仅作调试用途，后续可酌情清理或加 lint 抑制注释。

编写id_ex_reg.v,确认无 stall 端口为设计意图——load-use 冒险时该级插入气泡（flush），而非保持，与 hazard 模块配合逻辑自洽。模块实现无误。

完成alu.v的编写，未编写tb

## 2026-3-26

完成hazard_unit.v编写
修正顶层模块的命名

## 2026-3-27

### 修复BUG、优化
* Bug 1 — forward_unit.v：
    ALU B 前递块错误赋值给 fwd_a
    优化默认值命名，提升可读性
* Bug 2 — ctrl.v：
    case 分支使用十进制字面量，永远不会匹配
    R型指令操作码错误，应为0110011
    R 型和 I 型 ALU 指令 alu_op_d 未根据 funct3/funct7 解码
    LUI / AUIPC 的 alu_op_d 未设置
* mem_wb_reg.v：
    端口名与顶层例化不一致
    更新初值命名
    删除无用的rs2_in
* hazard_unit.v:
    模块自包含自身文件
    修复清空逻辑与分支冒险，分离 if_id_reg 和 id_ex_reg 的清空信号，修复逻辑

* dmem.v:
    SB/SH写入忽略字内字节偏移，影响：SB/SH清除同字中其他字节数据
    always@(*)中使用非阻塞赋值<=，影响：仿真/综合行为不一致，读延迟一拍
    改为：
    按字节偏移 alu_out[1:0] 写入正确位置
    组合逻辑使用阻塞赋值 =，并加 default 防 latch

    ** AI：dmem 模块 Load 指令读取逻辑严重错误 (忽略了地址偏移)
    缺陷描述：
    在 dmem 模块的读逻辑中，当你执行 LB, LBU, LH, LHU 等非对齐或部分字读取时，代码永远只读取了内存字的最低位字节或最低半字，完全忽略了地址的低两位 alu_out[1:0] 。例如，读取字节时，代码写死为 dmem[alu_out[11:2]][7:0] ，这意味着无论你要读地址 0x00 还是 0x01，它返回的永远是 0x00 地址所在的最低字节数据
    dmem 模块中组合逻辑潜在的 Latch 问题
    缺陷描述：
    代码注释中写了“组合逻辑使用阻塞赋值 =，并加 default 防 latch” 。但是，在 always @(*) 块中，最外层包含了一个 if (mem_re) 条件判断，如果 mem_re 为 0（即不读内存时），dmem_rdata 没有被赋予任何值 。这会导致综合器推断出锁存器（Latch），影响时序。
    AI修复的已加入源文件

* imm_gen.v:
    增加默认值

* if_id_reg:
    stall时不赋值即为保持，删除冗余自赋值
    在 if_id_reg 中，else if (stall) 的优先级高于 else if (flush) 。考虑这种情况：分支预测错误需要冲刷（flush = 1），但同时当前错误路径上的指令又触发了 Load-Use 停顿（stall = 1）。此时 if_id_reg 会被保持（Stall），而不是被清空（Flush），导致幽灵指令进入流水线
    调换stall，flush优先级
    将 input flush, 改为 input flush_if_id,防止在顶层连线时搞混

* id_ex_reg:
    将 input flush, 改为 input flush_id_ex

* riscv_top.v:
    修正fwd_br_a, fwd_br_b信号，拓展为2位，以及相应的组合逻辑
    更新连线