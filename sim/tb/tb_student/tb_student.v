`timescale 1ns/1ps
// =====================================================================
//  tb_student —— CPU 仿真测试平台
//
//  平台五要素:
//    ① 时钟/复位生成
//    ② 官方顶层 student_top 原样例化(和上板同一个壳)
//    ③ DRAM 镜像对账:tb 独立维护一份 DRAM 副本,每笔写同步记账,
//       每个 word load 写回前与镜像核对,快速路径读错立刻报警
//    ④ 运行监视:数码管写事件捕获、真实退休指令计数、自动停机
//    ⑤ 性能统计:引出 CPU 内部计数器,结束时打印周期/CPI/停顿分类
//
//  常用命令行参数(vsim):
//    +irom=xx.hex  指令镜像      +dram=xx.hex  数据镜像
//    +instr=N      退休N条后停   +full         跑完整程序
//
//  注:$display 打印串保持英文——中文 Windows 下 ModelSim 控制台按
//     GBK 解码会乱码;注释不参与打印,不受影响。
// =====================================================================
module tb_student;

  // ---- ①② 时钟/复位 与 官方顶层例化 ----
  reg         cpu_clk = 1'b0;      // CPU 主时钟,10ns 周期
  reg         clk50   = 1'b0;      // 官方壳需要的 50MHz 时钟
  reg         rst     = 1'b1;      // 复位:开局拉高 20 拍后释放
  reg  [63:0] sw      = 64'd0;     // 虚拟拨码开关(仿真不用,置0)
  reg  [ 7:0] key     = 8'd0;      // 虚拟按键(仿真不用,置0)
  wire [31:0] led;                 // 虚拟 LED
  wire [39:0] seg;                 // 虚拟数码管

  student_top dut (
      .w_cpu_clk(cpu_clk), .w_clk_50Mhz(clk50), .w_clk_rst(rst),
      .virtual_key(key), .virtual_sw(sw), .virtual_led(led), .virtual_seg(seg)
  );

  always #5 cpu_clk = ~cpu_clk;    // 每 5ns 翻转一次 → 100MHz
  always #5 clk50   = ~clk50;

  // ---- 运行参数与计数变量 ----
  localparam [31:0] SEG_ADDR = 32'h8020_0020;   // 数码管 MMIO 地址
  localparam [31:0] DR_M     = 32'h8010_0030;   // M扩展通过计数落点(期望8)
  localparam integer CAP     = 2_000_000_000;   // 周期上限保险丝

  integer     cyc          = 0;                 // 已运行周期数
  integer     idle         = 0;                 // PC 连续不动的拍数(判停用)
  reg [31:0]  pc_prev      = 32'hFFFF_FFFF;
  reg [31:0]  seg_val      = 32'hFFFF_FFFF;     // 数码管当前显示值
  integer     instr_target = 1000000;           // 退休指令目标(+instr=覆盖)
  reg         run_full     = 1'b0;              // +full:跑到程序自然结束
  reg [63:0]  real_instr   = 0;                 // 真实退休指令数(剔除气泡)

  // ---- ③ DRAM 镜像对账(平台的核心校验) ----
  // 思想:tb 当"会计",陪 CPU 记一本平行账。CPU 每写一笔 DRAM,账本同步记
  // 一笔;CPU 每读回一个字,翻账本核对。store缓冲/L0/投机读任何一条快速
  // 路径读错数,这里立刻 MIR-MISMATCH 报警——覆盖全部访存路径。
  integer sb_mismatch = 0, ld_checked = 0;      // 失配数(必须为0) / 已对账load数
  reg [31:0] mirror [0:65535];                  // 账本:与DRAM同大小,65536字=256KB
  reg [1023:0] mir_file;
  integer mi;
  initial begin                                 // 开局:清零后装载与DRAM相同的初值
    for (mi = 0; mi < 65536; mi = mi + 1) mirror[mi] = 32'h0;
    if (!$value$plusargs("dram=%s", mir_file)) mir_file = "sim/dram.hex";
    $readmemh(mir_file, mirror);
  end

  wire [15:0] mir_wa = dut.perip_addr[17:2];    // 字节地址砍掉低2位 → 字号
  // 记账:CPU 每写一笔 DRAM,按写宽度把同样内容记进镜像
  always @(posedge cpu_clk) begin : mirror_wr
    if (!rst && dut.perip_wen && dut.perip_addr >= 32'h8010_0000
                              && dut.perip_addr <= 32'h8013_FFFF) begin
      case (dut.perip_mask)
        2'b00: case (dut.perip_addr[1:0])       // 字节写sb:低2位地址选改哪8位
                 2'b00: mirror[mir_wa][ 7: 0] <= dut.perip_wdata[7:0];
                 2'b01: mirror[mir_wa][15: 8] <= dut.perip_wdata[7:0];
                 2'b10: mirror[mir_wa][23:16] <= dut.perip_wdata[7:0];
                 2'b11: mirror[mir_wa][31:24] <= dut.perip_wdata[7:0];
               endcase
        2'b01: if (dut.perip_addr[1])           // 半字写sh:addr[1]选上/下半
                    mirror[mir_wa][31:16] <= dut.perip_wdata[15:0];
               else mirror[mir_wa][15: 0] <= dut.perip_wdata[15:0];
        default:    mirror[mir_wa]        <= dut.perip_wdata;   // 整字写sw
      endcase
    end
  end

  // 对账:每个 DRAM word load 在 MEM1 拍核对"实际将写回的值"
  reg [31:0] exp_word, got_word;
  always @(posedge cpu_clk) begin : mirror_chk
    if (!rst && dut.Core_cpu.m1_mem_re && !dut.Core_cpu.dram_stall
        && (dut.Core_cpu.m1_mem_width == 2'b10)
        && dut.Core_cpu.m1_alu_out >= 32'h8010_0000
        && dut.Core_cpu.m1_alu_out <= 32'h8013_FFFF) begin
      ld_checked = ld_checked + 1;
      exp_word = mirror[dut.Core_cpu.m1_alu_out[17:2]];   // 账本上记的值
      // CPU 实际读到的值:投机读/store直传的数据在 mem1_fwd_reg,普通读在 m1_mem_rdata
      got_word = (dut.Core_cpu.m1_spec_rd || dut.Core_cpu.m1_st2ld_fwd)
               ? dut.Core_cpu.mem1_fwd_reg : dut.Core_cpu.m1_mem_rdata;
      if (got_word !== exp_word) begin          // !== 四态比较:未知态X也算不同
        sb_mismatch = sb_mismatch + 1;
        $display("[MIR-MISMATCH] cyc=%0d addr=%08x got=%08x exp=%08x",
                 cyc, dut.Core_cpu.m1_alu_out, got_word, exp_word);
      end
    end
  end

  // ---- ⑤ 性能计数器引出(计数器都在 CPU 的 u_perf 里,这里起短名) ----
  `define PC_CYC   dut.Core_cpu.u_perf.perf_cycles
  `define PC_RET   dut.Core_cpu.u_perf.perf_instret
  `define PC_BRT   dut.Core_cpu.u_perf.perf_branch_total
  `define PC_BRM   dut.Core_cpu.u_perf.perf_branch_mispred
  `define PC_JMT   dut.Core_cpu.u_perf.perf_jump_total
  `define PC_JMM   dut.Core_cpu.u_perf.perf_jump_mispred
  `define PC_DRAM  dut.Core_cpu.u_perf.perf_dram_stall_cyc
  `define PC_LU    dut.Core_cpu.u_perf.perf_load_use_stall_cyc
  `define PC_MDU   dut.Core_cpu.u_perf.perf_mdu_stall_cyc
  // Load-Use 停顿按"生产者所在流水级"归因
  `define PC_LU_E1LD  dut.Core_cpu.u_perf.perf_lu_e1ld
  `define PC_LU_E1MUL dut.Core_cpu.u_perf.perf_lu_e1mul
  `define PC_LU_E2LD  dut.Core_cpu.u_perf.perf_lu_e2ld
  `define PC_LU_E2MUL dut.Core_cpu.u_perf.perf_lu_e2mul
  `define PC_LU_M1    dut.Core_cpu.u_perf.perf_lu_m1

  // 结束时打印统计报表(图12 截取的就是这段输出)
  task dump_perf;
    reg [63:0] c, r;
    begin
      c = `PC_CYC; r = `PC_RET;
      $display("======================= PERF =======================");
      $display(" retired instr  = %0d   cycles = %0d", r, c);
      if (r != 0) $display(" CPI x1000      = %0d", (c*1000)/r);
      $display(" REAL instr     = %0d   (real CPI x1000 = %0d)",
               real_instr, (real_instr!=0)?(c*1000)/real_instr:0);
      $display(" --- branches ---");
      $display(" branch total   = %0d   mispred = %0d   (rate x10000 = %0d)",
               `PC_BRT, `PC_BRM, (`PC_BRT!=0)?((`PC_BRM*64'd10000)/`PC_BRT):0);
      $display(" jump   total   = %0d   mispred = %0d   (rate x10000 = %0d)",
               `PC_JMT, `PC_JMM, (`PC_JMT!=0)?((`PC_JMM*64'd10000)/`PC_JMT):0);
      $display(" --- stall cycles (and %% of cycles, x10000) ---");
      $display(" dram_stall     = %0d   (%0d)", `PC_DRAM, (c!=0)?((`PC_DRAM*64'd10000)/c):0);
      $display(" load_use_stall = %0d   (%0d)", `PC_LU,   (c!=0)?((`PC_LU*64'd10000)/c):0);
      $display(" mdu_stall      = %0d   (%0d)", `PC_MDU,  (c!=0)?((`PC_MDU*64'd10000)/c):0);
      $display(" --- load_use breakdown (stall cycles by stage) ---");
      $display("   EX1.load  = %0d", `PC_LU_E1LD);
      $display("   EX1.pmul  = %0d", `PC_LU_E1MUL);
      $display("   EX2.load  = %0d", `PC_LU_E2LD);
      $display("   EX2.pmul  = %0d", `PC_LU_E2MUL);
      $display("   MEM1.load = %0d", `PC_LU_M1);
      $display(" --- cycle accounting: real + stalls + mispredict == total? ---");
      $display("   cycles=%0d  real_instr=%0d  stalls=%0d  residual(=mispredict)=%0d  events=%0d",
               c, real_instr, `PC_LU + `PC_MDU + `PC_DRAM,
               c - real_instr - `PC_LU - `PC_MDU - `PC_DRAM,
               `PC_BRM + `PC_JMM);
      $display(" final SEG = %08x   RV32I(37)=%02x  M(8)=%01x  time=%05x",
               seg_val, seg_val[31:24], seg_val[23:20], seg_val[19:0]);
      $display(" ld_checked = %0d   MIR-MISMATCH = %0d   (must be 0)", ld_checked, sb_mismatch);
      $display("====================================================");
      $fflush;
    end
  endtask

  // ---- ④ 运行监视与自动停机 ----
  always @(posedge cpu_clk) begin
    if (!rst) begin
      cyc = cyc + 1;
      // 真实退休:WB 级本拍推进,且不是流水线插入的气泡(全0/NOP)
      if (!dut.Core_cpu.stall_back_prev && dut.Core_cpu.w_instr !== 32'h0
          && dut.Core_cpu.w_instr !== 32'h00000013)
        real_instr = real_instr + 1;

      // 数码管写事件捕获:值有变化才记录一行
      if (dut.perip_wen && dut.perip_addr == SEG_ADDR && dut.perip_wdata !== seg_val) begin
        seg_val = dut.perip_wdata;
        $display("[SEG] cyc=%0d  value=%08x", cyc, seg_val); $fflush;
      end
      // 正确性早信号:M 扩展通过计数写进 DRAM 时提前报出来(期望8)
      if (dut.perip_wen && dut.perip_addr == DR_M)
        begin $display("[DRAM 0x80100030 <= %0d] cyc=%0d (expect 8)", dut.perip_wdata, cyc); $fflush; end

      // 长跑心跳:每 500 万拍报一次进度,证明没卡死
      if (cyc % 5000000 == 0) begin
        $display("[hb ] cyc=%0d  retired=%0d  pc=%08x  seg=%08x", cyc, `PC_RET, dut.pc, seg_val); $fflush;
      end

      // 停机条件三选一:退休数达标 / PC 原地自旋(程序结束) / 周期保险丝
      if (dut.pc === pc_prev) idle = idle + 1; else idle = 0;
      pc_prev = dut.pc;
      if (!run_full && `PC_RET >= instr_target) begin
        $display("\n==== CHECKPOINT: retired %0d instructions ====", instr_target);
        dump_perf; $finish;
      end else if (idle > 2000 && cyc > 100) begin
        $display("\n==== DONE (PC spin at %08x) ====", dut.pc);
        dump_perf; $finish;
      end else if (cyc >= CAP) begin
        $display("\n==== CAP REACHED ====");
        dump_perf; $finish;
      end
    end
  end

  // ---- 命令行参数解析 与 复位释放 ----
  initial begin
    if ($value$plusargs("instr=%d", instr_target))
      $display("instr_target = %0d", instr_target);
    if ($test$plusargs("full")) begin run_full = 1'b1; $display("RUN-TO-COMPLETION mode"); end
    rst = 1'b1;
    repeat (20) @(posedge cpu_clk);
    rst = 1'b0;
  end

endmodule
