// ============================================================================
// tb_myCPU.sv
// 简化版仿真平台：
//   1. IROM 读 imem.hex，给 CPU 取指。
//   2. DRAM 读 dmem.hex，给 CoreMark 等程序使用。
//   3. TEST_MODE=1 时，额外打开低地址内存，适配 riscv-tests。
//   4. 0xF000_0000/0xF000_0004 分别作为 magic UART / EXIT。
// ============================================================================
`timescale 1ns / 1ps

module tb_myCPU #(
    parameter IROM_HEX   = "imem.hex",
    parameter DRAM_HEX   = "dmem.hex",
    parameter MAX_CYCLES = 64'd200_000_000,
    parameter TEST_MODE  = 0
) ();

  // 时钟复位：100MHz，复位 100ns 后释放
  reg clk = 1'b0;
  reg rst = 1'b1;
  always #5 clk = ~clk;

  initial begin
    #100 rst = 1'b0;
  end

  // DUT 接口
  wire [31:0] irom_addr, irom_data;
  wire [31:0] perip_addr, perip_wdata, perip_rdata;
  wire        perip_wen;
  wire [ 1:0] perip_mask;

  myCPU u_cpu (
      .cpu_rst    (rst),
      .cpu_clk    (clk),
      .irom_addr  (irom_addr),
      .irom_data  (irom_data),
      .perip_addr (perip_addr),
      .perip_wen  (perip_wen),
      .perip_mask (perip_mask),
      .perip_wdata(perip_wdata),
      .perip_rdata(perip_rdata)
  );

  // --------------------------------------------------------------------------
  // 内存模型
  // --------------------------------------------------------------------------
  localparam IROM_WORDS = 16384;              // 64KB
  localparam DRAM_WORDS = 65536;              // 256KB
  localparam DRAM_BASE  = 32'h8010_0000;

  reg [31:0] irom_mem [0:IROM_WORDS-1];       // 取指 ROM
  reg [31:0] low_mem  [0:IROM_WORDS-1];       // riscv-tests 低地址数据区
  reg [31:0] dram_mem [0:DRAM_WORDS-1];       // CoreMark 数据区
  reg [31:0] dram_rdata_q;

  initial begin : init_mem
    integer i;
    for (i = 0; i < IROM_WORDS; i = i + 1) begin
      irom_mem[i] = 32'h0000_0013;            // NOP
      low_mem[i]  = 32'h0000_0013;
    end
    for (i = 0; i < DRAM_WORDS; i = i + 1)
      dram_mem[i] = 32'h0;

    $readmemh(IROM_HEX, irom_mem);
    $readmemh(IROM_HEX, low_mem);
    $readmemh(DRAM_HEX, dram_mem);
    $display("[TB] IROM = %s", IROM_HEX);
    $display("[TB] DRAM = %s", DRAM_HEX);
  end

  assign irom_data = irom_mem[irom_addr[15:2]];

  wire in_low_mem = (TEST_MODE == 1) &&
                    ((perip_addr < 32'h0001_0000) ||
                     (perip_addr >= 32'h8000_0000 &&
                      perip_addr <  32'h8001_0000));
  wire in_dram    = (perip_addr >= DRAM_BASE) &&
                    (perip_addr <  DRAM_BASE + 32'h0004_0000);

  wire [13:0] low_idx = perip_addr[15:2];
  wire [15:0] dram_idx = perip_addr[17:2];
  wire [ 1:0] byte_off = perip_addr[1:0];

  // 根据访存宽度和地址低两位生成字节写使能
  function automatic [3:0] byte_enable;
    input [1:0] width;
    input [1:0] off;
    begin
      case (width)
        2'b00:   byte_enable = 4'b0001 << off;                 // byte
        2'b01:   byte_enable = 4'b0011 << {off[1], 1'b0};      // half
        default: byte_enable = 4'b1111;                        // word
      endcase
    end
  endfunction

  // store byte/half 时，把低位数据扩展到每个可能写入的字节 lane
  function automatic [31:0] expand_wdata;
    input [31:0] data;
    input [1:0]  width;
    begin
      case (width)
        2'b00:   expand_wdata = {4{data[7:0]}};
        2'b01:   expand_wdata = {2{data[15:0]}};
        default: expand_wdata = data;
      endcase
    end
  endfunction

  // 按字节写使能合并新旧 word
  function automatic [31:0] write_merge;
    input [31:0] old_word;
    input [31:0] new_word;
    input [3:0]  be;
    begin
      write_merge = old_word;
      if (be[0]) write_merge[ 7: 0] = new_word[ 7: 0];
      if (be[1]) write_merge[15: 8] = new_word[15: 8];
      if (be[2]) write_merge[23:16] = new_word[23:16];
      if (be[3]) write_merge[31:24] = new_word[31:24];
    end
  endfunction

  // load byte/half/word 时，把目标字节/半字取到低位；符号扩展由 CPU 内部完成
  function automatic [31:0] read_align;
    input [31:0] word;
    input [1:0]  width;
    input [1:0]  off;
    begin
      case (width)
        2'b00: begin
          case (off)
            2'b00:   read_align = {24'h0, word[ 7: 0]};
            2'b01:   read_align = {24'h0, word[15: 8]};
            2'b10:   read_align = {24'h0, word[23:16]};
            default: read_align = {24'h0, word[31:24]};
          endcase
        end
        2'b01:   read_align = off[1] ? {16'h0, word[31:16]} :
                                         {16'h0, word[15: 0]};
        default: read_align = word;
      endcase
    end
  endfunction

  wire [3:0]  mem_be    = byte_enable(perip_mask, byte_off);
  wire [31:0] mem_wdata = expand_wdata(perip_wdata, perip_mask);

  // 写内存；DRAM 读数据打一拍，模拟同步读 RAM
  always @(posedge clk) begin
    if (perip_wen && in_low_mem)
      low_mem[low_idx] <= write_merge(low_mem[low_idx], mem_wdata, mem_be);

    if (perip_wen && in_dram)
      dram_mem[dram_idx] <= write_merge(dram_mem[dram_idx], mem_wdata, mem_be);

    dram_rdata_q <= dram_mem[dram_idx];
  end

  assign perip_rdata = in_low_mem ? read_align(low_mem[low_idx], perip_mask, byte_off) :
                        in_dram    ? read_align(dram_rdata_q,   perip_mask, byte_off) :
                                     32'h0;

  // --------------------------------------------------------------------------
  // magic IO：CoreMark 用 UART 打印，用 EXIT 结束仿真
  // --------------------------------------------------------------------------
  localparam MAGIC_UART = 32'hF000_0000;
  localparam MAGIC_EXIT = 32'hF000_0004;

  always @(posedge clk) begin
    if (!rst && perip_wen) begin
      if (perip_addr == MAGIC_UART) begin
        $write("%c", perip_wdata[7:0]);
        $fflush;
      end
      if (perip_addr == MAGIC_EXIT && perip_wdata != 32'h0) begin
        dump_perf("EXIT");
        $finish;
      end
    end
  end

  // 防止程序跑飞后仿真无限等待
  reg [63:0] tick = 64'd0;
  always @(posedge clk) begin
    if (rst) tick <= 64'd0;
    else begin
      tick <= tick + 64'd1;
      if (tick == MAX_CYCLES) begin
        $display("\n[TB] TIMEOUT: MAX_CYCLES=%0d", MAX_CYCLES);
        dump_perf("TIMEOUT");
        $finish;
      end
    end
  end

  // riscv-tests 约定：x26=1 表示结束，x27=1 表示通过，x3 保存失败编号
  generate
    if (TEST_MODE == 1) begin : g_riscv_tests
      initial begin
        @(negedge rst);
        forever begin
          @(posedge clk);
          if (u_cpu.u_regfile.rf[26] === 32'h1) begin
            repeat (10) @(posedge clk);
            if (u_cpu.u_regfile.rf[27] === 32'h1)
              $display("\n[TB] PASS (cycles=%0d)", u_cpu.perf_cycles);
            else
              $display("\n[TB] FAIL testnum=%0d (cycles=%0d)",
                       u_cpu.u_regfile.rf[3], u_cpu.perf_cycles);
            $finish;
          end
        end
      end
    end
  endgenerate

  // 统一打印性能计数器
  task automatic dump_perf(input string tag);
    real cpi, br_acc, jmp_acc;
    begin
      cpi = (u_cpu.perf_instret == 0) ? 0.0 :
            $itor(u_cpu.perf_cycles) / $itor(u_cpu.perf_instret);
      br_acc = (u_cpu.perf_branch_total == 0) ? 0.0 :
               100.0 * (u_cpu.perf_branch_total - u_cpu.perf_branch_mispred) /
               u_cpu.perf_branch_total;
      jmp_acc = (u_cpu.perf_jump_total == 0) ? 0.0 :
                100.0 * (u_cpu.perf_jump_total - u_cpu.perf_jump_mispred) /
                u_cpu.perf_jump_total;

      $display("");
      $display("================ PERFORMANCE [%s] ================", tag);
      $display(" cycles  : %0d", u_cpu.perf_cycles);
      $display(" instret : %0d", u_cpu.perf_instret);
      $display(" CPI     : %.3f", cpi);
      $display(" branch  : total=%0d mispred=%0d acc=%.2f%%",
               u_cpu.perf_branch_total, u_cpu.perf_branch_mispred, br_acc);
      $display(" jump    : total=%0d mispred=%0d acc=%.2f%%",
               u_cpu.perf_jump_total, u_cpu.perf_jump_mispred, jmp_acc);
      $display(" stalls  : dram=%0d load_use=%0d mdu=%0d",
               u_cpu.perf_dram_stall_cyc,
               u_cpu.perf_load_use_stall_cyc,
               u_cpu.perf_mdu_stall_cyc);
      $display("==================================================");
    end
  endtask

endmodule
