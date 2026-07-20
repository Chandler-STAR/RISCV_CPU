`include "../include/defines.vh"
// store_buffer: 4项小缓冲,记最近写过的字地址和数据
// load的地址撞上了就直接给数,不用等存储器读回,后面的指令少停一拍
// 数据同时也写进了存储器
// 只做了字的缓存！
module store_buffer #(
    parameter N = 8,
    parameter AW = 16            // DRAM 字地址位宽 = addr[17:2]
) (
    input  wire           clk,
    input  wire           rst,

    // ---- store 侧 (MEM1 提交，非投机) ----
    input  wire           st_en,      // DRAM 区写 (m1_mem_we && m1 在 DRAM 区)
    input  wire           st_word,    // 该写是 word (m1_mem_width==WORD)
    input  wire [AW-1:0]  st_waddr,   // m1_alu_out[17:2]
    input  wire [31:0]    st_wdata,   // m1_rs2 (写入的整字)

    // ---- load 侧 (EX2 组合查找) ----
    input  wire           ld_en,      // DRAM 区 word 读 (e2_mem_re && e2 在 DRAM 区 && word)
    input  wire [AW-1:0]  ld_raddr,   // e2_alu_out[17:2]
    output wire           ld_hit,
    output wire [31:0]    ld_data,

    // ---- 第二查找口(EX1 组合查找,地址来自译码级预测并打拍) ----
    // 只管报命中和给数;能不能用(同拍有store在写这类情况)由外面判断。
    input  wire [AW-1:0]  ld2_raddr,
    output wire           ld2_hit,
    output wire [31:0]    ld2_data
);
    integer i;
    reg              valid [0:N-1];
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
            if (valid[i] && addr[i] == st_waddr) begin
                st_match = 1'b1;
                st_match_idx = i[$clog2(N)-1:0];
            end
    end

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

    // ---- load 侧：组合查找 ----
    reg              hit_c;
    reg  [31:0]      data_c;
    always @(*) begin
        hit_c  = 1'b0;
        data_c = 32'h0;
        for (i = 0; i < N; i = i + 1)
            if (valid[i] && addr[i] == ld_raddr) begin
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
            if (valid[i] && addr[i] == ld2_raddr) begin
                hit2_c  = 1'b1;
                data2_c = data[i];
            end
    end
    assign ld2_hit  = hit2_c;
    assign ld2_data = data2_c;

endmodule
