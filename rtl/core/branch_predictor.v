// module branch_predictor (
//     input  clk,
//     input  rst_n,
//     input  [31:0] pc,
// );

// endmodule //branch_predictor
module branch_predictor #(
    parameter PC_WIDTH = 32,
    parameter BHT_SIZE = 256,  // 256条记录
    parameter BHT_IDX_W = 8  // log2(BHT_SIZE)
) (
    input wire clk,
    input wire rst,

    // IF 阶段：预测接口
    input  wire [PC_WIDTH-1:0] if_pc,
    //向 IF/ID寄存器输出预测结果，两个周期后由传递到 EX 阶段进行验证
    output reg                 predict_taken,
    output reg  [PC_WIDTH-1:0] predict_target,

    // EX 阶段：更新接口
    input wire                ex_is_branch,     // 是一条分支指令
    input wire [PC_WIDTH-1:0] ex_pc,            // 分支指令的PC
    input wire                ex_actual_taken,  // 实际是否跳转
    input wire [PC_WIDTH-1:0] ex_actual_target  // 实际跳转目标
);

  // 内部存储结构
  reg  [          1:0] bht_counters                                                  [BHT_SIZE-1:0];
  reg  [ PC_WIDTH-1:0] btb_target                                                    [BHT_SIZE-1:0];
  reg  [ PC_WIDTH-1:0] btb_tag                                                       [BHT_SIZE-1:0];
  //valid位表示该BTB条目是否有效，初始为无效，只有当分支指令被执行后才会被设置为有效
  reg                  btb_valid                                                     [BHT_SIZE-1:0];

  wire [BHT_IDX_W-1:0] if_idx = if_pc[BHT_IDX_W+1:2];  // 忽略低两位的对齐位
  wire [BHT_IDX_W-1:0] ex_idx = ex_pc[BHT_IDX_W+1:2];

  // --- IF 阶段：组合逻辑查询 ---
  always @(*) begin
    if (btb_valid[if_idx] && btb_tag[if_idx] == if_pc) begin
      // 如果 BTB 命中，看 BHT 的最高位（10/11 为跳转）
      predict_taken  = bht_counters[if_idx][1];
      predict_target = btb_target[if_idx];
    end else begin
      // 以下为冗余代码，在顶层中若predict_taken  = 1'b0成立则pc_next直接取pc4，不会使用predict_target，因此这里predict_target的值无关紧要，但为了保持逻辑清晰和避免潜在的综合工具警告，仍然将其设置为一个合理的默认值（顺序执行的下一个地址）
      predict_taken  = 1'b0;
      predict_target = if_pc + 4;  // 默认顺序执行
    end
  end

  // --- EX 阶段：更新逻辑 ---
  integer i;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      for (i = 0; i < BHT_SIZE; i = i + 1) begin
        bht_counters[i] <= 2'b01; // 初始设为弱不跳转
        btb_valid[i]    <= 1'b0;
      end
    end else if (ex_is_branch) begin
      // 1. 更新 BTB 目标
      btb_valid[ex_idx]  <= 1'b1;
      btb_tag[ex_idx]    <= ex_pc;
      btb_target[ex_idx] <= ex_actual_target;

      // 2. 更新 BHT 饱和计数器
      case (bht_counters[ex_idx])
        2'b00: bht_counters[ex_idx] <= ex_actual_taken ? 2'b01 : 2'b00;
        2'b01: bht_counters[ex_idx] <= ex_actual_taken ? 2'b10 : 2'b00;
        2'b10: bht_counters[ex_idx] <= ex_actual_taken ? 2'b11 : 2'b01;
        2'b11: bht_counters[ex_idx] <= ex_actual_taken ? 2'b11 : 2'b10;
      endcase
    end
  end

endmodule
