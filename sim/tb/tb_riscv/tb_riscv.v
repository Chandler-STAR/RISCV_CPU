`timescale 1ns/1ps
// riscv-tests 运行台：直接例化 myCPU + 统一 16KB 内存（冯·诺依曼），
// 复刻 dram_driver 的「读按 offset+mask 抽取低位 / 写按字节使能」语义。
// 测试用例 PC 相对(auipc)，代码在低字、数据在 +0x1000；取指与数据口都按 addr[13:2]
// 索引同一 16KB 窗口，故 reset PC=0x80000000 的高位被屏蔽，代码落 mem[0]、数据落 mem[0x400+]。
// 判定：测试结尾 `j self`，PC 卡住后看 s11(x27)=1 通过 / 0 失败（s10/x26=1 表示已结束）。
module tb_riscv;
  reg cpu_clk = 0, cpu_rst = 1;
  always #5 cpu_clk = ~cpu_clk;     // 100MHz 仿真（频率无关，只看功能）

  wire [31:0] irom_addr, irom_addr2, perip_addr, perip_wdata;
  wire [31:0] perip_raddr_w;
  wire        perip_wen;
  wire [1:0]  perip_mask;
  reg  [31:0] irom_data, irom_data2, perip_rdata, perip_rdram;

  myCPU dut (
    .cpu_rst(cpu_rst), .cpu_clk(cpu_clk),
    .irom_addr(irom_addr), .irom_data(irom_data),
    .irom_addr2(irom_addr2), .irom_data2(irom_data2),
    .perip_addr(perip_addr), .perip_raddr(perip_raddr_w), .perip_wen(perip_wen), .perip_mask(perip_mask),
    .perip_wdata(perip_wdata), .perip_rdata(perip_rdata), .perip_rdram(perip_rdram)
  );

  // 统一内存：4K 字 = 16KB
  reg [31:0] mem [0:4095];
  integer k;

  // 取指：组合读（与 IROM spo 一致）
  // TNS-D:取指改 BRAM latency-1(地址寄存),与真实 irom_bram 同步读一致
  always @(posedge cpu_clk) irom_data <= mem[irom_addr[13:2]];
  // 双发取指 B 口(pc|4),与 A 口同为 latency-1
  always @(posedge cpu_clk) irom_data2 <= mem[irom_addr2[13:2]];
  // W-EE:B口裸读模型(latency-1;riscv 地址不在 DRAM 区,EE 命中恒 0,此口仅保编译/时序一致)
  always @(posedge cpu_clk) perip_rdram <= mem[perip_raddr_w[13:2]];

  // 数据读：组合（7 级非 DRAM 区 load 期望同拍 perip_rdata），按 offset+mask 抽取
  wire [11:0] dw   = perip_addr[13:2];
  wire [1:0]  roff = perip_addr[1:0];
  wire [31:0] rwd  = mem[dw];
  always @(*) begin
    case (perip_mask)
      2'b00: case (roff)
               2'b00: perip_rdata = {24'b0, rwd[7:0]};
               2'b01: perip_rdata = {24'b0, rwd[15:8]};
               2'b10: perip_rdata = {24'b0, rwd[23:16]};
               default: perip_rdata = {24'b0, rwd[31:24]};
             endcase
      2'b01: perip_rdata = roff[1] ? {16'b0, rwd[31:16]} : {16'b0, rwd[15:0]};
      default: perip_rdata = rwd;
    endcase
  end

  // 数据写：组合 EX 地址，同步写（store 在 EX→MEM 沿提交）
  wire [1:0] woff = perip_addr[1:0];
  wire [3:0] wea = perip_wen ? (
      (perip_mask==2'b00) ? (4'b0001 << woff) :
      (perip_mask==2'b01) ? (4'b0011 << {woff[1],1'b0}) : 4'b1111) : 4'b0000;
  wire [31:0] wal = (perip_mask==2'b00) ? {4{perip_wdata[7:0]}} :
                    (perip_mask==2'b01) ? {2{perip_wdata[15:0]}} : perip_wdata;
  always @(posedge cpu_clk) begin
    if (wea[0]) mem[dw][7:0]   <= wal[7:0];
    if (wea[1]) mem[dw][15:8]  <= wal[15:8];
    if (wea[2]) mem[dw][23:16] <= wal[23:16];
    if (wea[3]) mem[dw][31:24] <= wal[31:24];
  end

  // ---- 加载用例 + 跑 + 判定 ----
  // 判定：riscv-tests 约定 x26(s10) 全程=0，仅 pass/fail 处置 1（结束标志）；
  // x27(s11)=1 通过 / 0 失败。检测 rf[26]==1 后再等 20 拍让 rf[27] 落定。
  reg [1023:0] testf, name;
  integer cyc = 0, done_cnt = 0;
  reg done_seen = 0;

  initial begin
    for (k=0;k<4096;k=k+1) mem[k]=32'h0;
    if (!$value$plusargs("test=%s", testf)) begin $display("NO +test"); $finish; end
    if (!$value$plusargs("name=%s", name)) name = "test";
    $readmemh(testf, mem);
    repeat (8) @(posedge cpu_clk);
    cpu_rst = 0;
  end

  always @(posedge cpu_clk) begin
    cyc <= cyc + 1;
    if (!cpu_rst) begin
      if (dut.u_regfile.rf[26] === 32'd1) done_seen <= 1'b1;
      if (done_seen) done_cnt <= done_cnt + 1;
      if (done_cnt > 20) begin
        if (dut.u_regfile.rf[27] === 32'd1)
          $display("RVTEST %0s RESULT=PASS  cyc=%0d", name, cyc);
        else
          $display("RVTEST %0s RESULT=FAIL  s11=%0d gp=%0d pc=%08x cyc=%0d",
                   name, dut.u_regfile.rf[27], dut.u_regfile.rf[3], irom_addr, cyc);
        $finish;
      end
      if (cyc > 300000) begin
        $display("RVTEST %0s RESULT=TIMEOUT pc=%08x", name, irom_addr); $finish;
      end
    end
  end
endmodule
