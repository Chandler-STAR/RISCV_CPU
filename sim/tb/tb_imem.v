`timescale 1ns/1ps  // 定义仿真时间单位：1ns，精度1ps

module tb_imem;

// 1. 信号声明（与imem模块接口一一对应）
reg [31:0] pc;          // 输入：程序计数器PC
wire [31:0] instr_if;   // 输出：读取的32位指令

// 2. 实例化待测试模块（DUT）
// 注意：替换file_path为你实际的指令文件路径（如"./instructions.hex"）
imem #(
    .file_path("C:/Users/zyx316/Desktop/git-demo/RISCV_CPU/sim/tb/instructions.hex")  // 指令文件路径（必填，需提前创建）
) u_imem (
    .pc(pc),
    .instr_if(instr_if)
);

// 3. 仿真测试流程（initial块仅执行一次）
initial begin
    // ===== 步骤1：初始化信号 =====
    pc = 32'h00000000;  // 初始PC设为0
    $display("===== 开始测试imem模块 =====");

    // ===== 步骤2：等待存储器初始化 =====
    #10;  // 等待$readmemh加载指令文件完成

    // ===== 步骤3：测试不同PC地址 =====
    // 测试PC=0（对应存储器地址0）
    pc = 32'h00000000;
    #5;
    $display("PC = 0x%08h, 读取指令 = 0x%08h", pc, instr_if);

    // 测试PC=4（对应存储器地址1，字对齐）
    pc = 32'h00000004;
    #5;
    $display("PC = 0x%08h, 读取指令 = 0x%08h", pc, instr_if);

    // 测试PC=0x100（对应存储器地址64）
    pc = 32'h00000100;
    #5;
    $display("PC = 0x%08h, 读取指令 = 0x%08h", pc, instr_if);

    // 测试边界PC=0x1FFC（对应存储器地址1023，最大地址）
    pc = 32'h00001FFC;
    #5;
    $display("PC = 0x%08h, 读取指令 = 0x%08h", pc, instr_if);

    // 测试非对齐PC（低2位非0，验证仅取[11:2]）
    pc = 32'h00000002;
    #5;
    $display("PC = 0x%08h (非对齐), 读取指令 = 0x%08h", pc, instr_if);

    // ===== 步骤4：结束仿真 =====
    #10;
    $display("===== imem模块测试完成 =====");
    $finish;  // 终止仿真
end

endmodule