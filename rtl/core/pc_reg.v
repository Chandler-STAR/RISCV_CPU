`include "../include/defines.vh"

// 程序计数器 —— IF阶段
module pc_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,          // load-use停顿（冻结PC）
    input  wire        redirect,       // 分支跳转（覆盖stall，强制更新PC）
    input  wire [31:0] pc_next,        // 下一PC：跳转目标 或 PC+4
    output reg  [31:0] pc
);


    always @(posedge clk) begin
        if (rst)
            pc <= 32'h8000_0000;      
        else if (redirect)
            pc <= pc_next;             // 分支跳转不受stall影响
        else if (!stall)
            pc <= pc_next;
    end

endmodule
