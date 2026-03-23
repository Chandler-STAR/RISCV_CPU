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