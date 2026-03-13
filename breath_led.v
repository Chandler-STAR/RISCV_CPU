module breath_led (
    input          sys_clk,
    input          sys_rst_n,
    input          touch_key,
    output reg     led
);

parameter   CLK_2us_MAX = 7'd100;
reg [9:0]   CLK_2s_MAX= 10'd1000;
reg [6:0]   cnt_2us;
reg [9:0]   cnt_2ms;
reg [9:0]   cnt_2s;
reg         inc_dec_flag;

//计数器计时2us
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        cnt_2us <= 7'b0;
    else if(cnt_2us == CLK_2us_MAX - 7'b1)
        cnt_2us <= 7'b0;
    else
        cnt_2us <= cnt_2us + 7'b1;
end

//计数器计时2ms
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        cnt_2ms <= 10'b0;
    else if((cnt_2ms == CLK_2s_MAX - 10'b1) && (cnt_2us == CLK_2us_MAX - 7'b1))
        cnt_2ms <= 10'b0;
    else if(cnt_2us == CLK_2us_MAX - 7'b1)
        cnt_2ms <= cnt_2ms + 10'b1;
end

//计数器计时2s
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        cnt_2s <= 10'b0;
    else if((cnt_2s == CLK_2s_MAX - 10'b1) && (cnt_2ms == CLK_2s_MAX - 10'b1) && (cnt_2us == CLK_2us_MAX - 7'b1))
        cnt_2s <= 10'b0;
    else if((cnt_2ms == CLK_2s_MAX - 10'b1) && (cnt_2us == CLK_2us_MAX - 7'b1))
        cnt_2s <= cnt_2s + 10'b1;
end

//亮度递增\递减标志
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        inc_dec_flag <= 1'b0;
    else if((cnt_2s == CLK_2s_MAX - 10'b1) && (cnt_2ms == CLK_2s_MAX - 10'b1) && (cnt_2us == CLK_2us_MAX - 7'b1))
        inc_dec_flag <= ~inc_dec_flag;
    else
        inc_dec_flag = inc_dec_flag;
end

//控制LED输出
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        led <= 1'b0;
    else if(((inc_dec_flag == 1'b1) && (cnt_2ms >= cnt_2s)) || ((inc_dec_flag == 1'b0) && (cnt_2ms <= cnt_2s)))
        led <= 1'b1;
    else
        led <= 1'b0;
end

reg touch_key_d0;
reg touch_key_d1;

wire pos_touch_key;

assign pos_touch_key = ~touch_key_d1 & touch_key_d0;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)  begin
        touch_key_d0 <= 1'b0;
        touch_key_d1 <= 1'b0;
    end
    else begin
        touch_key_d0 <= touch_key;
        touch_key_d1 <= touch_key_d0;
    end
end

always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)  begin
        CLK_2s_MAX <= 10'd1000;
    end
    else if(pos_touch_key) begin
        CLK_2s_MAX <= CLK_2s_MAX - 10'd100;
    end
end


endmodule