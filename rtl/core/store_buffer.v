`include "../include/defines.vh"
// store_buffer: 4项小缓冲,记最近写过的字地址和数据
// load的地址撞上了就直接给数,不用等存储器读回,后面的指令少停一拍
// 数据同时也写进了存储器
// SUBWORD_FAST 版:条目带4位字节掩码,sb/sh 也登记并按字节合并;
//   load 命中 = 地址匹配 且 需要的字节全被掩码覆盖(写通策略下缓冲字节与存储器恒一致)。
//   数据输出仍是整字,车道提取/符号扩展由外部捕获点统一做。
// 旧版(关掉宏):只缓存字,byte/half store 命中→作废条目。
module store_buffer #(
    parameter N = 8,
    parameter AW = 16            // DRAM 字地址位宽 = addr[17:2]
) (
    input  wire           clk,
    input  wire           rst,

    // ---- store 侧 (MEM1 提交，非投机) ----
    input  wire           st_en,      // DRAM 区写 (m1_mem_we && m1 在 DRAM 区)
`ifdef SUBWORD_FAST
    input  wire [3:0]     st_mask,    // 本次写覆盖的字节道(word=1111,与BRAM字节使能同语义)
`else
    input  wire           st_word,    // 该写是 word (m1_mem_width==WORD)
`endif
    input  wire [AW-1:0]  st_waddr,   // m1_alu_out[17:2]
    input  wire [31:0]    st_wdata,   // 写数据(SUBWORD_FAST 下已按道复制对齐)

    // ---- load 侧 (EX2 组合查找) ----
    input  wire           ld_en,      // DRAM 区读
    input  wire [AW-1:0]  ld_raddr,   // e2_alu_out[17:2]
`ifdef SUBWORD_FAST
    input  wire [3:0]     ld_need,    // 本次读需要的字节道
`endif
    output wire           ld_hit,
    output wire [31:0]    ld_data,

    // ---- 第二查找口(EX1 组合查找,地址来自译码级预测并打拍) ----
    // 只管报命中和给数;能不能用(同拍有store在写这类情况)由外面判断。
    input  wire [AW-1:0]  ld2_raddr,
`ifdef SUBWORD_FAST
    input  wire [3:0]     ld2_need,
`endif
    output wire           ld2_hit,
    output wire [31:0]    ld2_data
);
    integer i;
`ifdef SUBWORD_FAST
    reg  [3:0]       mask  [0:N-1];   // 0000 = 无效
`else
    reg              valid [0:N-1];
`endif
    reg  [AW-1:0]    addr  [0:N-1];
    reg  [31:0]      data  [0:N-1];
    reg  [$clog2(N)-1:0] alloc_ptr;

    // ---- store 侧：找同址条目 (update-if-exists, 否则环形分配) ----
    reg              st_match;
    reg  [$clog2(N)-1:0] st_match_idx;
    always @(*) begin
        st_match = 1'b0;
        st_match_idx = {$clog2(N){1'b0}};
        for (i = 0; i < N; i = i + 1)
`ifdef SUBWORD_FAST
            if (mask[i] != 4'b0 && addr[i] == st_waddr) begin
`else
            if (valid[i] && addr[i] == st_waddr) begin
`endif
                st_match = 1'b1;
                st_match_idx = i[$clog2(N)-1:0];
            end
    end

`ifdef SUBWORD_FAST
    // 掩码版:命中→按字节合并;未命中→环形分配(掩码只标写过的字节)。
    // "每地址至多一个条目"不变量保持:只在无匹配时分配。
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < N; i = i + 1) mask[i] <= 4'b0;
            alloc_ptr <= {$clog2(N){1'b0}};
        end else if (st_en) begin
            if (st_match) begin
                if (st_mask[0]) data[st_match_idx][ 7: 0] <= st_wdata[ 7: 0];
                if (st_mask[1]) data[st_match_idx][15: 8] <= st_wdata[15: 8];
                if (st_mask[2]) data[st_match_idx][23:16] <= st_wdata[23:16];
                if (st_mask[3]) data[st_match_idx][31:24] <= st_wdata[31:24];
                mask[st_match_idx] <= mask[st_match_idx] | st_mask;
            end else begin
                addr[alloc_ptr] <= st_waddr;
                data[alloc_ptr] <= st_wdata;   // 未覆盖字节是复制残值,掩码挡住不读
                mask[alloc_ptr] <= st_mask;
                alloc_ptr <= alloc_ptr + 1'b1;
            end
        end
    end
`else
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < N; i = i + 1) valid[i] <= 1'b0;
            alloc_ptr <= {$clog2(N){1'b0}};
        end else if (st_en) begin
            if (st_word) begin
                // word store：更新已有条目，否则环形分配新条目
                if (st_match) begin
                    data[st_match_idx] <= st_wdata;
                end else begin
                    valid[alloc_ptr] <= 1'b1;
                    addr [alloc_ptr] <= st_waddr;
                    data [alloc_ptr] <= st_wdata;
                    alloc_ptr <= alloc_ptr + 1'b1;
                end
            end else begin
                // byte/half store：整字值变脏 → 作废同址条目
                if (st_match) valid[st_match_idx] <= 1'b0;
            end
        end
    end
`endif

    // ---- load 侧：组合查找 ----
    reg              hit_c;
    reg  [31:0]      data_c;
    always @(*) begin
        hit_c  = 1'b0;
        data_c = 32'h0;
        for (i = 0; i < N; i = i + 1)
`ifdef SUBWORD_FAST
            if (mask[i] != 4'b0 && addr[i] == ld_raddr
                && ((ld_need & ~mask[i]) == 4'b0)) begin
`else
            if (valid[i] && addr[i] == ld_raddr) begin
`endif
                hit_c  = 1'b1;
                data_c = data[i];
            end
    end
    // 在途 store 冒险：同拍同址 store → 缓冲未更新，强制 miss 走 BRAM
    wire inflight_haz = st_en && (st_waddr == ld_raddr);
    assign ld_hit  = ld_en && hit_c && !inflight_haz;
    assign ld_data = data_c;

    // ---- 第二个查找口:纯组合匹配(能不能用由外面判断) ----
    reg              hit2_c;
    reg  [31:0]      data2_c;
    always @(*) begin
        hit2_c  = 1'b0;
        data2_c = 32'h0;
        for (i = 0; i < N; i = i + 1)
`ifdef SUBWORD_FAST
            if (mask[i] != 4'b0 && addr[i] == ld2_raddr
                && ((ld2_need & ~mask[i]) == 4'b0)) begin
`else
            if (valid[i] && addr[i] == ld2_raddr) begin
`endif
                hit2_c  = 1'b1;
                data2_c = data[i];
            end
    end
    assign ld2_hit  = hit2_c;
    assign ld2_data = data2_c;

endmodule
