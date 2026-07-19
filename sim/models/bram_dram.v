// =====================================================================
//  bram_dram —— Vivado 简单双口 BRAM IP 的行为级仿真模型（仅仿真用）
//  A 口只写(wea/addra/dina)、B 口只读(addrb/doutb)，latency-1。
//   读口无字节写回 mux → 真实 IP 读路径少 ~0.6ns(EX1→w_mem_rdata 是 Fmax 最差路径)。
//   A/B 同地址、一拍一次访问(load 走 B 读、store 走 A 写，不同拍)；store 时 B 口 doutb 无用。
//   读写同址同拍=READ_FIRST(读旧值)，但只在 store 发生(doutb 无用)，故 collision 行为无关紧要。
// =====================================================================
module bram_dram #(
    parameter HEX = "sim/dram.hex"
) (
    input  wire        clka,
    input  wire        ena,
    input  wire [ 3:0] wea,
    input  wire [15:0] addra,
    input  wire [31:0] dina,
    input  wire        clkb,
    input  wire        enb,
    input  wire [15:0] addrb,
    output reg  [31:0] doutb
);
  reg [31:0] mem [0:65535];            // 256KB = 64K 字
  integer k;
  reg [1023:0] dram_file;
  initial begin
    for (k = 0; k < 65536; k = k + 1) mem[k] = 32'h0;
    if (!$value$plusargs("dram=%s", dram_file)) dram_file = HEX;
    $readmemh(dram_file, mem);
    doutb = 32'h0;
  end

  // A 口：字节写
  always @(posedge clka) begin
    if (ena) begin
      if (wea[0]) mem[addra][ 7: 0] <= dina[ 7: 0];
      if (wea[1]) mem[addra][15: 8] <= dina[15: 8];
      if (wea[2]) mem[addra][23:16] <= dina[23:16];
      if (wea[3]) mem[addra][31:24] <= dina[31:24];
    end
  end

  // B 口：只读，latency-1，READ_FIRST（NBA 读到本拍写之前的旧值）
  always @(posedge clkb) begin
    if (enb) doutb <= mem[addrb];
  end
endmodule
