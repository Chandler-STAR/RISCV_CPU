// ras —— 返回地址栈(Return Address Stack),只存一层:记住最近一次 call 的返回地址,
// 取指遇到 ret 直接拿它当预测目标,不用等流水线读寄存器。测试程序调用浅,一层几乎全中;
// 猜错由 EX2 核对真目标并冲刷重取,只多花几拍不会算错。(原名 branch_predictor)
module ras (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall_back,      // MEM1 反压时不更新

    // EX2 提交侧:只有已提交的 call 才写栈顶
    input  wire        ex_is_branch,    // EX2 是分支或跳转
    input  wire [ 1:0] ex_instr_type,   // 00=Branch 01=Jump 10=Call 11=Ret
    input  wire [31:0] ex_pc,

    output wire [31:0] ras_top_o
);
  localparam TYPE_CALL = 2'b10;

  reg [31:0] ras_top_r;                 // 单入口:无栈数组、无指针、无弹栈

  assign ras_top_o = ras_top_r;

  always @(posedge clk or posedge rst) begin
    if (rst) ras_top_r <= 32'd0;
    else if (!stall_back && ex_is_branch && ex_instr_type == TYPE_CALL)
      ras_top_r <= ex_pc + 32'd4;       // ret 不弹栈:扁平热循环够用,嵌套 miss 由 EX2 兜
  end
endmodule
