`include "../include/defines.vh"

// IF→ID 流水线寄存器
// 七级流水:IF→ROM→ID→EX1→EX2→MEM1→WB
module if_id_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,              // 预测错/异常:下一拍给ID送气泡
    input  wire        stall,              // 停顿:保持不动
    input  wire [31:0] pc_in,
    input  wire [31:0] pc4_in,
    input  wire [31:0] instr_in,
    input  wire        predict_taken_in,   // 分支预测：是否预测跳转
    input  wire [31:0] predict_target_in,  // 分支预测：预测目标地址
    input  wire        fused_in,          // 宏操作融合
    input  wire        valid_in,          // head_v:队头确实有一条真指令，非硬件产生的气泡
    input  wire [31:0] imm_ovr_in,         //immediate overwrite 融合:预合成的 32 位常数，非跳转条件下lui+addi融合为一条指令，矩阵乘法这种指令尤其多
    input  wire        imm_ovr_en_in,      //融合:立即数改写使能
    output reg  [31:0] d_pc,
    output reg  [31:0] d_pc4,
    output reg  [31:0] d_instr,
    output reg         d_predict_taken,    // 传递预测结果到ID
    output reg  [31:0] d_predict_target,
    output reg         d_fused,
    output reg  [31:0] d_imm_ovr,
    output reg         d_imm_ovr_en,
    output reg         d_valid          // 队头有真指令
);

    always @(posedge clk) begin
        if (rst) begin
            d_pc             <= 32'h8000_0000;
            d_pc4            <= 32'h8000_0004;
            d_instr          <= `INST_NOP;
            d_predict_taken  <= 1'b0;
            d_predict_target <= 32'h8000_0004;
            d_fused          <= 1'b0;
            d_imm_ovr        <= 32'd0;
            d_imm_ovr_en     <= 1'b0;
            d_valid          <= 1'b0;
        end else if (flush) begin
            d_pc             <= 32'd0;
            d_pc4            <= 32'd0;
            d_instr          <= `INST_NOP;
            d_predict_taken  <= 1'b0;
            d_predict_target <= 32'd0;
            d_fused          <= 1'b0;
            d_imm_ovr_en     <= 1'b0;
            d_valid          <= 1'b0;
        end else if (stall) begin
            d_pc             <= d_pc;
            d_pc4            <= d_pc4;
            d_instr          <= d_instr;
            d_predict_taken  <= d_predict_taken;
            d_predict_target <= d_predict_target;
            d_fused          <= d_fused;
            d_imm_ovr        <= d_imm_ovr;
            d_imm_ovr_en     <= d_imm_ovr_en;
            d_valid          <= d_valid;
        end else begin
            d_pc             <= pc_in;
            d_pc4            <= pc4_in;
            d_instr          <= instr_in;
            d_predict_taken  <= predict_taken_in;
            d_predict_target <= predict_target_in;
            d_fused          <= fused_in;
            d_valid          <= valid_in;
            d_imm_ovr        <= imm_ovr_in;
            d_imm_ovr_en     <= imm_ovr_en_in;
        end
    end

endmodule
