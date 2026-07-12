`include "../include/defines.vh"
// l0_cache: 128项小缓存,记最近读过/写过的字地址和数据(直接映射)
// load的地址撞上了就提前给数,后面的指令一拍不停;没撞上也没代价,照常走存储器
// 记的数据存储器里同步都有(写穿),两边永远一致,所以命中只会更快不会错
// 只记整字;字节/半字写到某一项就把它作废,免得数据不完整。上电全空
module l0_cache (
    input  wire        clk,
    input  wire        rst,

    // 执行级查询口(组合读:索引来自寄存器,路径很浅)
    input  wire [15:0] ld_raddr,      // 译码级预测出的 load 字地址([17:2])
    output wire        ld_hit,
    output wire [31:0] ld_data,

    // 访存级填充口(load 结果 / word store 写穿 / 子字 store 作废)
    input  wire        wr_en,         // 填充:写入地址+数据并置有效
    input  wire        wr_inv,        // 作废:仅清该索引的有效位
    input  wire [15:0] wr_addr,       // 字地址([17:2])
    input  wire [31:0] wr_data
);

  reg [31:0]  data_mem [0:127];       // 数据体(分布式 RAM)
  reg [ 8:0]  tag_mem  [0:127];       // 标签体(字地址高 9 位)
  reg [127:0] vld;                    // 有效位(触发器,复位清空)

  // 查询:索引读出 + 标签比较,一层查找表深度
  wire [6:0] ridx = ld_raddr[6:0];
  assign ld_hit  = vld[ridx] && (tag_mem[ridx] == ld_raddr[15:7]);
  assign ld_data = data_mem[ridx];

  // 填充/作废共用一个写口(load 与 store 不会同拍出现在访存级)
  wire [6:0] widx = wr_addr[6:0];
  always @(posedge clk) begin
    if (rst) begin
      vld <= 128'd0;
    end else if (wr_en) begin
      data_mem[widx] <= wr_data;
      tag_mem[widx]  <= wr_addr[15:7];
      vld[widx]      <= 1'b1;
    end else if (wr_inv) begin
      vld[widx]      <= 1'b0;
    end
  end

endmodule
