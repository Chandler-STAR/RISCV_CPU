`include "../include/defines.vh"

// IF→ID 流水线寄存器
// 7级流水线：IF→ID→EX1→EX2→MEM1→MEM2→WB
module if_id_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,
    input  wire        stall,
    input  wire [31:0] pc_in,
    input  wire [31:0] pc4_in,
    input  wire [31:0] instr_in,
    input  wire        predict_taken_in,   // 分支预测：是否预测跳转
    input  wire [31:0] predict_target_in,  // 分支预测：预测目标地址
    output reg  [31:0] d_pc,
    output reg  [31:0] d_pc4,
    output reg  [31:0] d_instr,
    output reg         d_predict_taken,    // 传递预测结果到ID
    output reg  [31:0] d_predict_target
);

    always @(posedge clk) begin
        if (rst) begin
            d_pc             <= 32'h8000_0000;
            d_pc4            <= 32'h8000_0004;
            d_instr          <= `INST_NOP;
            d_predict_taken  <= 1'b0;
            d_predict_target <= 32'h8000_0004;
        end else if (flush) begin
            d_pc             <= 32'd0;
            d_pc4            <= 32'd0;
            d_instr          <= `INST_NOP;
            d_predict_taken  <= 1'b0;
            d_predict_target <= 32'd0;
        end else if (stall) begin
            d_pc             <= d_pc;
            d_pc4            <= d_pc4;
            d_instr          <= d_instr;
            d_predict_taken  <= d_predict_taken;
            d_predict_target <= d_predict_target;
        end else begin
            d_pc             <= pc_in;
            d_pc4            <= pc4_in;
            d_instr          <= instr_in;
            d_predict_taken  <= predict_taken_in;
            d_predict_target <= predict_target_in;
        end
    end

endmodule
