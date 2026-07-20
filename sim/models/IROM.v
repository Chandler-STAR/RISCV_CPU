// =====================================================================
//  irom_bram —— Vivado blk_mem ROM IP 的行为级仿真模型(仅仿真用)
//  接口与 student_top 中实例化的 irom_bram 一致:clka / addra(12位字地址) / douta(32位)
//  同步读(latency-1,地址寄存),匹配真实 BRAM ROM(无输出寄存器)。
//  旧的分布式 ROM 模型(IROM/spo 组合读)已随 IP 更换退役。
// =====================================================================
module irom_bram #(
    parameter HEX = "sim/irom.hex"     // 由 COE/irom-v2.coe 转换而来
) (
    input  wire        clka,
    input  wire [11:0] addra,
    output reg  [31:0] douta
);
  reg [31:0] rom [0:4095];             // 16KB = 4096 字
  integer k;
  reg [1023:0] irom_file;
  initial begin
    for (k = 0; k < 4096; k = k + 1) rom[k] = 32'h00000013; // 默认 NOP
    // +irom=<path> 可覆盖默认镜像(仿真用,方便跑 src0/1/2)
    if (!$value$plusargs("irom=%s", irom_file)) irom_file = HEX;
    $readmemh(irom_file, rom);
    douta = 32'h00000013;
  end
  always @(posedge clka) douta <= rom[addra];
endmodule
