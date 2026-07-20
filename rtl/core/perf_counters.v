`include "../include/defines.vh"
// =====================================================================
//  perf_counters —— 纯统计计数器(零输出)
//
//  这个模块【没有任何输出】,因此综合时会被整块剪除,面积/时序代价为零。
//  它只被仿真台以层次引用读取:  dut.Core_cpu.u_perf.perf_<名>
//
//  为什么单独成模块:原先这 60 行散在 myCPU.sv 末尾,和 stall/flush 的全局
//  控制逻辑混在一起,让人误以为它参与电路。分出来之后,myCPU.sv 里剩下的
//  每一行都是真的会综合出门的东西。
//
//  注意:minstret 用的 instret_pulse / instret_dbl 【不在】这里 ——
//  它们是架构可见的(喂 csr_regfile),留在 myCPU.sv。
//
//  分桶之间可以重叠(例如同一拍 load_use_stall 同时命中 e1_ld 与 e2_ld 归因),
//  分析时不要把各桶相加当成总数。
// =====================================================================
module perf_counters (
    input wire        clk,
    input wire        rst,

    // ── 退休 ──
    input wire        instret_pulse,   // 写回级退休一条真指令(myCPU 算好送进来)

    // ── 分支/跳转(EX2 提交窗口)──
    input wire        e2_branch,
    input wire        e2_jump,
    input wire        predict_dir_wrong,
    input wire        predict_target_bad,
    input wire        predict_jump_bad,

    // ── 停顿源 ──
    input wire        stall_back,      // = dram_stall,MEM1 反压
    input wire        dram_stall,
    input wire        load_use_stall,
    input wire        mdu_stall,
    input wire        stall,           // 汇总停顿(load_use|dram|mdu|csr_raw)

    // ── load-use 停顿归因(来自 hazard_unit 的 dbg_* 输出)──
    input wire        hz_e1_ld,
    input wire        hz_e1_mul,
    input wire        hz_e2_ld,
    input wire        hz_e2_mul,
    input wire        hz_m1_ld,

    // ── 投机事件 ──
    input wire        mem_re_d,        // ID 是 load
    input wire [ 1:0] mem_width_d,
    input wire [ 2:0] fwd_a_pre,       // ID 的基址转发编码(≠FWD_NONE ⇒ 基址在途)
    input wire        d1_hit,          // EX1 提前查 store_buffer / l0_cache 命中
    input wire        predict_taken,   // 取指级预测跳转
    input wire        st_conflict,     // MEM1 store 与 EX2 load 同址
    input wire        e2_mem_re
);

  reg [31:0] perf_branch_total, perf_branch_mispred;
  reg [31:0] perf_jump_total,   perf_jump_mispred;
  reg [31:0] perf_dram_stall_cyc, perf_load_use_stall_cyc, perf_mdu_stall_cyc;
  reg [31:0] perf_lu_e1ld, perf_lu_e1mul, perf_lu_e2ld, perf_lu_e2mul, perf_lu_m1;
  reg [31:0] perf_ld_base_inflight;  // word load 的基址还在流水线里没落地 -> 放弃投机
  reg [31:0] perf_d1_hit;            // EX1 提前查 store_buffer / l0_cache 命中
  reg [31:0] perf_predict_taken;     // 取指级预测跳转的次数
  reg [31:0] perf_st_conflict;       // MEM1 的 store 与 EX2 的 load 同址
  reg [63:0] perf_cycles;
  reg [63:0] perf_instret;

  // 分支/跳转只在 EX2 真正推进的那一拍算一次提交
  wire perf_br_commit  = e2_branch && !stall_back;
  wire perf_jmp_commit = e2_jump   && !stall_back;
  wire perf_br_mis     = perf_br_commit  && (predict_dir_wrong || predict_target_bad);
  wire perf_jmp_mis    = perf_jmp_commit && predict_jump_bad;

  always @(posedge clk) begin
    if (rst) begin
      perf_cycles             <= 64'd0;
      perf_instret            <= 64'd0;
      perf_branch_total       <= 32'd0;
      perf_branch_mispred     <= 32'd0;
      perf_jump_total         <= 32'd0;
      perf_jump_mispred       <= 32'd0;
      perf_dram_stall_cyc     <= 32'd0;
      perf_load_use_stall_cyc <= 32'd0;
      perf_mdu_stall_cyc      <= 32'd0;
      perf_lu_e1ld  <= 32'd0; perf_lu_e1mul <= 32'd0;
      perf_lu_e2ld  <= 32'd0; perf_lu_e2mul <= 32'd0; perf_lu_m1 <= 32'd0;
      perf_ld_base_inflight <= 32'd0; perf_d1_hit  <= 32'd0;
      perf_predict_taken <= 32'd0; perf_st_conflict   <= 32'd0;
    end else begin
      perf_cycles     <= perf_cycles + 64'd1;
      if (instret_pulse)   perf_instret            <= perf_instret + 64'd1;
      if (perf_br_commit)  perf_branch_total       <= perf_branch_total   + 32'd1;
      if (perf_br_mis)     perf_branch_mispred     <= perf_branch_mispred + 32'd1;
      if (perf_jmp_commit) perf_jump_total         <= perf_jump_total     + 32'd1;
      if (perf_jmp_mis)    perf_jump_mispred       <= perf_jump_mispred   + 32'd1;
      if (dram_stall)      perf_dram_stall_cyc     <= perf_dram_stall_cyc + 32'd1;
      if (load_use_stall)  perf_load_use_stall_cyc <= perf_load_use_stall_cyc + 32'd1;
      if (mdu_stall)       perf_mdu_stall_cyc      <= perf_mdu_stall_cyc + 32'd1;

      // load-use 停顿归因(桶间可重叠)
      if (load_use_stall && hz_e1_ld)  perf_lu_e1ld  <= perf_lu_e1ld  + 32'd1;
      if (load_use_stall && hz_e1_mul) perf_lu_e1mul <= perf_lu_e1mul + 32'd1;
      if (load_use_stall && hz_e2_ld)  perf_lu_e2ld  <= perf_lu_e2ld  + 32'd1;
      if (load_use_stall && hz_e2_mul) perf_lu_e2mul <= perf_lu_e2mul + 32'd1;
      if (load_use_stall && hz_m1_ld)  perf_lu_m1    <= perf_lu_m1    + 32'd1;

      // 投机事件
      if (mem_re_d && (mem_width_d == `MEM_WORD) && (fwd_a_pre != `FWD_NONE) && !stall)
        perf_ld_base_inflight <= perf_ld_base_inflight + 32'd1;
      if (d1_hit && !stall_back)
        perf_d1_hit  <= perf_d1_hit + 32'd1;
      if (predict_taken && !stall)
        perf_predict_taken <= perf_predict_taken + 32'd1;
      if (st_conflict && e2_mem_re && !stall_back)
        perf_st_conflict   <= perf_st_conflict + 32'd1;
    end
  end

endmodule
