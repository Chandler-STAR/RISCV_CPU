`timescale 1ns / 1ps

// ================= 路径根据你的文件夹自动修正 =================
// 如果你的 tb 在 sim/tb，defines 在 include，就用这个
`include "../../../rtl/include/defines.vh"

module tb_if_id_reg();

parameter CLK_PERIOD = 10;  // 10ns 时钟

// 输入
reg         clk;
reg         rst;
reg         flush;
reg         stall;
reg [31:0]  pc_in;
reg [31:0]  pc4_in;
reg [31:0]  instr_in;

// 输出
wire [31:0] d_pc;
wire [31:0] d_pc4;
wire [31:0] d_instr;

// 例化被测试模块
if_id_reg u_if_id_reg (
    .clk      (clk),
    .rst      (rst),
    .flush    (flush),
    .stall    (stall),
    .pc_in    (pc_in),
    .pc4_in   (pc4_in),
    .instr_in (instr_in),
    
    .d_pc     (d_pc),
    .d_pc4    (d_pc4),
    .d_instr  (d_instr)
);

// 时钟生成
initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

reg         risk;
always @(posedge risk) begin
    stall <= 1'b1;
    flush <= 1'b1;
end
// 测试激励
initial begin
    // 初始化
    rst       = 1'b1;
    flush     = 1'b0;
    stall     = 1'b0;
    pc_in     = 32'd0;
    pc4_in    = 32'd0;
    instr_in  = 32'd0;
    risk      = 1'b0;

    #(CLK_PERIOD * 2);
    rst = 1'b0;          // 释放复位
    $display("0x%08h, 0x%08h, 0x%08h", d_pc, d_pc4,d_instr);
    #(CLK_PERIOD);

    // ======================
    // 1. 正常传输
    // ======================
    pc_in    = 32'h00000004;
    pc4_in   = 32'h00000008;
    instr_in = 32'h12345678;
    #(CLK_PERIOD);
    $display("0x%08h, 0x%08h, 0x%08h", d_pc, d_pc4,d_instr);

    pc_in    = 32'h00000008;
    pc4_in   = 32'h0000000C;
    instr_in = 32'h87654321;
    #(CLK_PERIOD);
    $display("0x%08h, 0x%08h, 0x%08h", d_pc, d_pc4,d_instr);

    // ======================
    // 2. 测试 STALL 保持
    // ======================
    stall = 1'b1;
    pc_in    = 32'h11111111;
    pc4_in   = 32'h22222222;
    instr_in = 32'h33333333;
    #(CLK_PERIOD * 2);
    $display("0x%08h, 0x%08h, 0x%08h", d_pc, d_pc4,d_instr);
    stall = 1'b0;
    #(CLK_PERIOD);

    // ======================
    // 3. 测试 FLUSH 清空
    // ======================
    flush = 1'b1;
    #(CLK_PERIOD);
    $display("0x%08h, 0x%08h, 0x%08h", d_pc, d_pc4,d_instr);
    flush = 1'b0;
    $display("0x%08h, 0x%08h, 0x%08h", d_pc, d_pc4,d_instr);
    #(CLK_PERIOD);

    // ======================
    // 4. 测试 FLUSH STALL 同时拉高
    // ======================
    pc_in    = 32'h00000008;
    pc4_in   = 32'h0000000C;
    instr_in = 32'h87654321;
    #(CLK_PERIOD);
    $display("0x%08h, 0x%08h, 0x%08h", d_pc, d_pc4,d_instr);

    #(CLK_PERIOD);
    
    risk = 1'b1;
    #(CLK_PERIOD);
    $display("0x%08h, 0x%08h, 0x%08h", d_pc, d_pc4,d_instr);
    risk = 1'b0;
    //$display("0x%08h, 0x%08h, 0x%08h", d_pc, d_pc4,d_instr);
    #(CLK_PERIOD);
    // ======================
    // 5. 再次复位
    // ======================
    rst = 1'b1;
    #(CLK_PERIOD);
    rst = 1'b0;
    #(CLK_PERIOD);

    // 结束
    #(CLK_PERIOD * 5);
    $display("=== Simulation Finished ===");
    $finish;
end

// 生成波形文件（ModelSim 可用）
initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_if_id_reg);
end

endmodule
