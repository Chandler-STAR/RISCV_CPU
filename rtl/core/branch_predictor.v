// module branch_predictor (
//     input  clk,
//     input  rst_n,
//     input  [31:0] pc,
// );

// endmodule //branch_predictor
// module branch_predictor #(
//     parameter PC_WIDTH = 32,
//     parameter BHT_SIZE = 256,  // 256条记录
//     parameter BHT_IDX_W = 8  // log2(BHT_SIZE)
// ) (
//     input wire clk,
//     input wire rst,

//     // IF 阶段：预测接口
//     input  wire [PC_WIDTH-1:0] if_pc,
//     //向 IF/ID寄存器输出预测结果，两个周期后由传递到 EX 阶段进行验证
//     output reg                 predict_taken,
//     output reg  [PC_WIDTH-1:0] predict_target,

//     // EX 阶段：更新接口
//     input wire                ex_is_branch,      // 是一条分支指令
//     input wire [PC_WIDTH-1:0] ex_pc,             // 分支指令的PC
//     input wire                ex_actual_taken,
//     input wire [PC_WIDTH-1:0] ex_actual_target,
//     input wire                stall_back         // DRAM停顿时禁止更新BHT
// );

//   // 内部存储结构 - 用initial块初始化，避免综合/仿真差异
//   reg     [         1:0] bht_counters[BHT_SIZE-1:0];
//   reg     [PC_WIDTH-1:0] btb_target  [BHT_SIZE-1:0];
//   reg     [PC_WIDTH-1:0] btb_tag     [BHT_SIZE-1:0];
//   reg                    btb_valid   [BHT_SIZE-1:0];

//   integer                init_i;
//   initial begin
//     for (init_i = 0; init_i < BHT_SIZE; init_i = init_i + 1) begin
//       bht_counters[init_i] = 2'b01;
//       btb_valid[init_i]    = 1'b0;
//     end
//   end
//   // 计算索引：使用PC的不同位进行异或，增加分布均匀性
//   wire [BHT_IDX_W-1:0] if_idx = if_pc[BHT_IDX_W+1:2] ^ if_pc[BHT_IDX_W+9:10];
//   wire [BHT_IDX_W-1:0] ex_idx = ex_pc[BHT_IDX_W+1:2] ^ ex_pc[BHT_IDX_W+9:10];

//   // --- IF 阶段：组合逻辑查询 ---
//   always @(*) begin
//     if (btb_valid[if_idx] && btb_tag[if_idx] == if_pc) begin
//       // 如果 BTB 命中，看 BHT 的最高位（10/11 为跳转）
//       predict_taken  = bht_counters[if_idx][1];
//       predict_target = btb_target[if_idx];
//     end else begin
//       // 以下为冗余代码，在顶层中若predict_taken  = 1'b0成立则pc_next直接取pc4，不会使用predict_target，因此这里predict_target的值无关紧要，但为了保持逻辑清晰和避免潜在的综合工具警告，仍然将其设置为一个合理的默认值（顺序执行的下一个地址）
//       predict_taken  = 1'b0;
//       predict_target = if_pc + 4;  // 默认顺序执行
//     end
//   end

//   // --- EX 阶段：更新逻辑 ---
//   always @(posedge clk) begin
//     if (rst) begin
//       // 初始化由initial块处理，此处仅复位可综合逻辑
//     end else if (ex_is_branch && !stall_back) begin  // DRAM停顿时禁止更新，防止重复计数
//       // 1. 更新 BTB 目标
//       btb_valid[ex_idx]  <= 1'b1;
//       btb_tag[ex_idx]    <= ex_pc;
//       btb_target[ex_idx] <= ex_actual_target;

//       // 2. 更新 BHT 饱和计数器
//       case (bht_counters[ex_idx])
//         2'b00: bht_counters[ex_idx] <= ex_actual_taken ? 2'b01 : 2'b00;
//         2'b01: bht_counters[ex_idx] <= ex_actual_taken ? 2'b10 : 2'b00;
//         2'b10: bht_counters[ex_idx] <= ex_actual_taken ? 2'b11 : 2'b01;
//         2'b11: bht_counters[ex_idx] <= ex_actual_taken ? 2'b11 : 2'b10;
//       endcase
//     end
//   end

// endmodule

// module branch_predictor #(
//     parameter PC_WIDTH  = 32,
//     parameter BHT_SIZE  = 256,
//     parameter BHT_IDX_W = 8,
//     parameter RAS_DEPTH = 8
// ) (
//     input wire clk,
//     input wire rst,

//     // IF 阶段：预测与推测性更新
//     input  wire [PC_WIDTH-1:0] if_pc,
//     output reg                 predict_taken,
//     output reg  [PC_WIDTH-1:0] predict_target,

//     // EX 阶段：训练与纠错
//     input wire                ex_is_branch,      // 指令是否为分支类型
//     input wire [         1:0] ex_instr_type,     // 实际指令类型
//     input wire [PC_WIDTH-1:0] ex_pc,
//     input wire                ex_actual_taken,
//     input wire [PC_WIDTH-1:0] ex_actual_target,
//     input wire                stall_back         // DRAM停顿时禁止更新BHT
// );

//   // 指令类型编码
//   localparam TYPE_BRANCH = 2'b00;
//   localparam TYPE_JUMP = 2'b01;
//   localparam TYPE_CALL = 2'b10;
//   localparam TYPE_RET = 2'b11;

//   // --- BTB & BHT 存储 ---
//   reg [1:0] bht_counters[BHT_SIZE-1:0];
//   reg [PC_WIDTH-1:0] btb_target[BHT_SIZE-1:0];
//   reg [PC_WIDTH-1:0] btb_tag[BHT_SIZE-1:0];
//   reg [1:0] btb_type[BHT_SIZE-1:0];
//   reg btb_valid[BHT_SIZE-1:0];

//   // --- RAS 存储与指针 ---
//   reg [PC_WIDTH-1:0] ras_stack[RAS_DEPTH-1:0];
//   reg [$clog2(RAS_DEPTH)-1:0] ras_ptr;  // 始终指向当前可用的栈顶数据

//   wire [BHT_IDX_W-1:0] if_idx = if_pc[BHT_IDX_W+1:2] ^ if_pc[BHT_IDX_W+9:10];
//   wire [BHT_IDX_W-1:0] ex_idx = ex_pc[BHT_IDX_W+1:2] ^ ex_pc[BHT_IDX_W+9:10];

//   // --- IF 阶段：组合逻辑（输出预测结果） ---
//   wire btb_hit = btb_valid[if_idx] && (btb_tag[if_idx] == if_pc);
//   wire [1:0] hit_type = btb_type[if_idx];

//   always @(*) begin
//     predict_taken  = 1'b0;
//     predict_target = if_pc + 4;

//     if (btb_hit) begin
//       case (hit_type)
//         TYPE_BRANCH: begin
//           predict_taken  = bht_counters[if_idx][1];
//           predict_target = btb_target[if_idx];
//         end
//         TYPE_JUMP, TYPE_CALL: begin
//           predict_taken  = 1'b1;
//           predict_target = btb_target[if_idx];
//         end
//         TYPE_RET: begin
//           predict_taken  = 1'b1;
//           predict_target = ras_stack[ras_ptr];  // 直接读取当前栈顶
//         end
//       endcase
//     end
//   end

//   // --- IF & EX 阶段：状态更新逻辑 ---
//   integer i;
//   always @(posedge clk or posedge rst) begin
//     if (rst) begin
//       ras_ptr <= 0;
//       for (i = 0; i < BHT_SIZE; i = i + 1) begin
//         bht_counters[i] <= 2'b01;
//         btb_valid[i]    <= 1'b0;
//       end
//     end else if (!stall_back) begin  // DRAM停顿时禁止更新，防止重复计数

//       // 1. IF 阶段：推测性更新 RAS (Speculative Update)
//       // 如果 BTB 命中，在 Fetch 阶段就移动指针
//       if (btb_hit) begin
//         if (hit_type == TYPE_CALL) begin
//           // Push: 指针上移，写入返回地址 (PC+4)
//           // 注意：这里为了逻辑清晰使用阻塞赋值的概念描述逻辑，实际需考虑时序
//           // 
//           ras_stack[(ras_ptr==RAS_DEPTH-1)?0 : ras_ptr+1] <= if_pc + 4;
//           ras_ptr <= (ras_ptr == RAS_DEPTH - 1) ? 0 : ras_ptr + 1;
//         end else if (hit_type == TYPE_RET) begin
//           // Pop: 指针下移
//           ras_ptr <= (ras_ptr == 0) ? RAS_DEPTH - 1 : ras_ptr - 1;
//         end
//       end

//       // 2. EX 阶段：训练 BTB (Training)
//       // 只有第一次执行该指令或预测错误后，EX 阶段会通过此逻辑修正 BTB
//       if (ex_is_branch) begin
//         btb_valid[ex_idx]  <= 1'b1;
//         btb_tag[ex_idx]    <= ex_pc;
//         btb_type[ex_idx]   <= ex_instr_type;
//         btb_target[ex_idx] <= ex_actual_target;

//         if (ex_instr_type == TYPE_BRANCH) begin
//           case (bht_counters[ex_idx])
//             2'b00: bht_counters[ex_idx] <= ex_actual_taken ? 2'b01 : 2'b00;
//             2'b01: bht_counters[ex_idx] <= ex_actual_taken ? 2'b10 : 2'b00;
//             2'b10: bht_counters[ex_idx] <= ex_actual_taken ? 2'b11 : 2'b01;
//             2'b11: bht_counters[ex_idx] <= ex_actual_taken ? 2'b11 : 2'b10;
//           endcase
//         end
//       end

//       // 3. (进阶) EX 阶段：纠错逻辑 (Misprediction Recovery)
//       // 如果 EX 发现 IF 阶段根据错误的 BTB 信息误更新了 RAS（例如把普通 Branch 当成了 Call）
//       // 此处应有逻辑恢复 ras_ptr，为保持示例简洁，此处略去复杂的恢复快照逻辑。
//     end
//   end

// endmodule
//256→16，，8→4
module branch_predictor #(
    parameter PC_WIDTH  = 32,
    parameter BHT_SIZE  = 256,
    parameter BHT_IDX_W = 8,
    parameter RAS_DEPTH = 8,    // RAS 深度，通常 8-16 即可满足大部分需求
    parameter GHR_WIDTH = 8
) (
    input wire clk,
    input wire rst,

    // IF 阶段：预测接口
    input  wire [PC_WIDTH-1:0] if_pc,
    //向 IF/ID寄存器输出预测结果，两个周期后由传递到 EX 阶段进行验证
    output reg                 predict_taken,
    output reg  [PC_WIDTH-1:0] predict_target,

    // EX 阶段：更新接口
    input wire ex_is_branch,  // 是否是跳转指令(Branch/J/Call/Ret)
    input wire [1:0] ex_instr_type,  // 指令类型: 00:Branch, 01:Jump, 10:Call, 11:Return
    input wire [PC_WIDTH-1:0] ex_pc,
    input wire ex_actual_taken,
    input wire [PC_WIDTH-1:0] ex_actual_target,
    input wire stall_back  // DRAM停顿时禁止更新BHT

);

  function [BHT_IDX_W-1:0] hash_pc;
    input [31:0] pc;
    input [GHR_WIDTH-1:0] GHR;
    integer i;
    reg [BHT_IDX_W-1:0] h;
    begin
      h = 0;
      for (i = 0; i + BHT_IDX_W <= 32; i = i + 2) begin
        h = h ^ pc[i+:BHT_IDX_W];
      end
      hash_pc = h ^ GHR[BHT_IDX_W-1:0];
    end
  endfunction


  // --- 指令类型定义 ---
  localparam TYPE_BRANCH = 2'b00;
  localparam TYPE_JUMP = 2'b01;
  localparam TYPE_CALL = 2'b10;
  localparam TYPE_RET = 2'b11;

  // --- 内部存储结构 ---
  reg [1:0] bht_counters[BHT_SIZE-1:0];
  reg [PC_WIDTH-1:0] btb_target[BHT_SIZE-1:0];
  reg [PC_WIDTH-1:0] btb_tag[BHT_SIZE-1:0];
  reg [1:0] btb_type[BHT_SIZE-1:0];  // 记录指令类型
  reg btb_valid[BHT_SIZE-1:0];

  // --- RAS 堆栈结构 ---
  reg [PC_WIDTH-1:0] ras_stack[RAS_DEPTH-1:0];
  reg [$clog2(RAS_DEPTH)-1:0] ras_ptr;  // 指向栈顶


  // GHR 寄存器
  reg [GHR_WIDTH-1:0] ghr;
  // 每个流水线阶段维持 GHR 值
  reg [GHR_WIDTH-1:0] ghr_at_ex1;  // EX1 阶段的 GHR (打一拍)
  reg [GHR_WIDTH-1:0] ghr_at_ex2;  // EX2 阶段的 GHR (打两拍)

  //使用CRC-like 哈希函数计算索引，增加分布均匀性，减少冲突
  wire [BHT_IDX_W-1:0] if_idx = hash_pc(if_pc, ghr);  // 索引时结合 GHR 增加分布均匀性
  wire [BHT_IDX_W-1:0] ex_idx = hash_pc(
      ex_pc, ghr_at_ex2
  );  // EX 阶段使用对应的 GHR 快照计算索引

  // --- IF 阶段：组合逻辑查询 ---
  always @(*) begin
    predict_taken  = 1'b0;
    predict_target = if_pc + 4;

    if (btb_valid[if_idx] && btb_tag[if_idx] == if_pc) begin
      case (btb_type[if_idx])
        TYPE_BRANCH: begin
          predict_taken  = bht_counters[if_idx][1];
          predict_target = btb_target[if_idx];
        end
        TYPE_JUMP, TYPE_CALL: begin
          predict_taken  = 1'b1;
          predict_target = btb_target[if_idx];
        end
        TYPE_RET: begin
          predict_taken  = 1'b1;
          predict_target = ras_stack[ras_ptr];  // 从 RAS 预测返回地址
        end
        default: ;
      endcase
    end
  end

  // --- EX 阶段：更新逻辑 ---
  integer i;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      ras_ptr <= 0;
      for (i = 0; i < BHT_SIZE; i = i + 1) begin
        bht_counters[i] <= 2'b01;
        btb_valid[i]    <= 1'b0;
        btb_type[i]     <= 2'b00;
      end
      for (i = 0; i < RAS_DEPTH; i = i + 1) ras_stack[i] <= 0;
    end else if (!stall_back) begin
      // 1. 训练/更新 BTB 和 BHT
      if (ex_is_branch) begin
        btb_valid[ex_idx]  <= 1'b1;
        btb_tag[ex_idx]    <= ex_pc;
        btb_type[ex_idx]   <= ex_instr_type;
        btb_target[ex_idx] <= ex_actual_target;

        // 仅对条件跳转更新饱和计数器
        if (ex_instr_type == TYPE_BRANCH) begin
          case (bht_counters[ex_idx])
            2'b00: bht_counters[ex_idx] <= ex_actual_taken ? 2'b01 : 2'b00;
            2'b01: bht_counters[ex_idx] <= ex_actual_taken ? 2'b10 : 2'b00;
            2'b10: bht_counters[ex_idx] <= ex_actual_taken ? 2'b11 : 2'b01;
            2'b11: bht_counters[ex_idx] <= ex_actual_taken ? 2'b11 : 2'b10;
          endcase
        end
      end

      // 2. RAS 维护逻辑 (基于实际执行结果更新)
      // 注意：为了简化，这里在 EX 阶段更新。高性能实现通常在 IF 阶段推测性更新并在误判时修复。
      if (ex_is_branch && ex_actual_taken) begin
        if (ex_instr_type == TYPE_CALL) begin
          // Push: 存储函数返回地址 (当前 PC + 4)
          ras_ptr <= (ras_ptr == RAS_DEPTH - 1) ? 0 : ras_ptr + 1;
          ras_stack[(ras_ptr==RAS_DEPTH-1)?0 : ras_ptr+1] <= ex_pc + 4;
        end else if (ex_instr_type == TYPE_RET) begin
          // Pop: 弹出地址
          ras_ptr <= (ras_ptr == 0) ? RAS_DEPTH - 1 : ras_ptr - 1;
        end
      end
    end
  end
  // GHR 传递（每个周期打拍）
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      ghr        <= 0;
      ghr_at_ex1 <= 0;
      ghr_at_ex2 <= 0;
    end else if (!stall_back) begin
      ghr_at_ex1 <= ghr;
      ghr_at_ex2 <= ghr_at_ex1;

      // EX2 阶段更新 GHR（仅条件分支）
      if (ex_is_branch && ex_instr_type == TYPE_BRANCH) begin
        ghr <= {ghr[GHR_WIDTH-2:0], ex_actual_taken};
      end
    end
  end

endmodule
