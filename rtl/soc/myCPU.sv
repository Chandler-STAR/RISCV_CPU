`include "../include/defines.vh"
// myCPU: 七级流水线RISC-V核,RV32I + M + Zicsr + Zba,单发射
// 七级流水:IF取指 -> ROM等指令存储器出数(BRAM同步读要一拍) -> ID译码 ->
//          EX1算术 -> EX2分支判断 -> MEM1访存 -> WB写回，若认为IF/ROM为一级也可以说为6级
// 分支在EX2解析,误预测惩罚4拍(冲刷前3级重新取指)
// 取指一次取两条,但不是双发射:多取的一条是喂给宏操作融合的
// (两条固定搭配的指令合并成一条,一个流水槽完成两条指令),执行和写回仍是单发射
// 三种访存加速机制,目的是隐藏存储器的读延迟:
//   1) 投机读: ID就预测好load的地址,EX1提前发给存储器(预测有守卫,猜不准就不猜,不会算错)
//   2) 提前读: EX2用算出来的真地址再发一次,兜底
//   3) store_buffer / l0_cache: 最近写过/读过的数据直接给,连存储器都不用去
// 命名:d_/e1_/e2_/m1_/w_=各流水级  fq_*=取指队列  f1/f2/f5=融合模式  spec_*=用预测地址

module myCPU (
    input wire cpu_rst,
    input wire cpu_clk,

    output wire [31:0] irom_addr,
    input  wire [31:0] irom_data,
    output wire [31:0] irom_addr2,   // 取指 B 口(pc|4):双发取指的第二读口
    input  wire [31:0] irom_data2,

    output wire [31:0] perip_addr,
    output wire [31:0] perip_raddr,   // DRAM 读口独立地址(读写分口,load 地址可提前送出)
    output wire        perip_wen,
    output wire [ 1:0] perip_mask,
    output wire [31:0] perip_wdata,
    input  wire [31:0] perip_rdata,
    input  wire [31:0] perip_rdram    // DRAM 读口原始数据(未经外设桥选择,供提前读直接捕获)
);

  // ==================== 1. 全局与控制信号声明 ====================
  wire clk = cpu_clk;
  wire rst = cpu_rst;


  wire stall, flush_if_id, flush_id_ex1;
  wire [2:0] fwd_a_pre, fwd_b_pre;   // 在 ID 就算好的转发编码
  wire [2:0] e1_fwd_a, e1_fwd_b;     // 打拍到 EX1 的转发选择（EX1 直接用）
  wire dram_range, dram_stall, stall_back;
  reg [1:0] dram_wait_cnt;
  reg       m1_ex2_rd;   // 前向声明:这条load的读地址EX2已提前发过(dram_need在定义前引用)
  wire        e2_sb_hit;            // 前向声明:store_buffer命中(EX1的转发选择器在定义处之前引用)
  wire [31:0] sb_ld_data;
  wire        e2_st2ld_fwd;             // 前向声明:store→load 同地址直传命中
  wire        e2_sb_range;          // 前向声明:EX2 地址落在 DRAM 区间
  wire        e2_spec_rd_hit;            // 前向声明:投机读命中(EX1 用预测地址发的读)
  reg         m1_st2ld_fwd;             // 前向声明:直传的 load 进入 MEM1
`ifdef SUBWORD_FAST
  reg         e2_d1_ld;                 // 前向声明:d1命中随载荷进EX2(已格式化数据接力进MEM1腿)
`endif
  wire [31:0] ras_top_o;            // 前向声明:返回地址栈栈顶,ret指令的预测跳转目标
  wire [31:0] pmul_out;                // 前向声明:流水乘结果,MEM1拍出来
  wire        e2_is_pmul, m1_is_pmul;   // 前向声明:流水乘标志位(EX1段在pmul例化之前引用)
  reg         spec_addr_valid;             // 前向声明:load地址已在ID预测好,EX1可以发投机读
  reg  [15:0] spec_ld_waddr;
`ifdef SUBWORD_FAST
  reg  [1:0]  spec_ld_lane;    // 前向声明:预测地址字内偏移(子字车道,断言/查表在定义处之前引用)
`endif
  reg  [31:0] d1_data_reg;             // 前向声明:EX1提前查表命中的load数据(转发选择器在定义处之前引用)

  // 冲突检测与预测信号
  wire predict_taken, predict_wrong;
  wire [31:0] predict_target;
  wire load_use_stall;

  // ==================== 2. 各流水线阶段信号声明 ====================

  // IF 阶段
  wire [31:0] pc, pc_next;   // 取指地址 与 下一拍的取指地址

  // ID 阶段
  wire [31:0] d_pc, d_pc4, d_instr, d_predict_target;
  wire d_predict_taken;
  wire [4:0] rs1_addr, rs2_addr, rd_addr_d;
  wire [31:0] rs1_rf, rs2_rf, imm;
  wire reg_we_d, mem_we_d, mem_re_d, branch_d, jump_d, alu_src_d, mem_sign_d, rs1_en_d, rs2_en_d;
  wire [1:0] wb_sel_d, mem_width_d;
  wire [4:0] alu_op_d;
  wire [1:0] d_instr_type;
  // Zicsr / Trap / M / B 译码输出
  wire       is_csr_d, csr_uimm_d, is_ecall_d, is_mret_d, is_mul_d, is_div_d;
  wire       use_pc_d;   // alu_a 选 PC 预译码（AUIPC/Branch/JAL）
  wire [1:0] csr_op_d;

  // EX1 阶段
  wire [31:0] e1_pc, e1_pc4, e1_instr, e1_rs1, e1_rs2, e1_imm, e1_predict_target;
  wire [4:0] e1_rd_addr;
  wire e1_reg_we, e1_mem_we, e1_mem_re, e1_branch, e1_jump, e1_alu_src, e1_mem_sign, e1_predict_taken;
  wire [1:0] e1_wb_sel, e1_mem_width, e1_instr_type;
  wire [ 4:0] e1_alu_op;
  wire [31:0] alu_out;
  wire branch_taken;
  // EX1 阶段 Zicsr/Trap/M/B 控制信号
  wire        e1_is_csr, e1_csr_uimm, e1_is_ecall, e1_is_mret, e1_is_mul, e1_is_div;
  wire        e1_use_pc;   // alu_a 选 PC
  wire [1:0]  e1_csr_op;


  // EX2 阶段
  wire [31:0] e2_pc, e2_pc4, e2_instr, e2_rs2, e2_alu_out, e2_predict_target;
  wire [4:0] e2_rd_addr;
  wire e2_reg_we, e2_mem_we, e2_mem_re, e2_branch, e2_jump, e2_branch_taken, e2_mem_sign, e2_predict_taken, e2_pc_sel;
  wire [1:0] e2_wb_sel, e2_mem_width, e2_instr_type;
  wire [31:0] e2_pc_target;
  wire e2_is_branch_or_jump;

  // MEM1 阶段
  wire [31:0] m1_pc4, m1_instr, m1_alu_out, m1_rs2;
  wire [4:0] m1_rd_addr;
  wire m1_reg_we, m1_mem_we, m1_mem_re, m1_mem_sign;
  wire [1:0] m1_wb_sel, m1_mem_width;
  wire [31:0] m1_mem_rdata;

  // WB 阶段
  wire [31:0] w_pc4, w_instr, w_alu_out, w_mem_rdata;
  wire [4:0] w_rd_addr;
  wire       w_reg_we;
  wire [1:0] w_wb_sel;
  // 真指令/气泡标志:气泡的指令字和真nop相同(32'h13),只能靠这一位区分,指令计数专用
  wire       d_valid, e1_valid, e2_valid, m1_valid, w_valid;

  wire [31:0] wb_data;   // 最终写回寄存器堆的值(ALU结果/load数据/pc+4 三选一)

  // CSR / Trap 信号
  wire [31:0] csr_rdata, mtvec_o, mepc_o;
  wire        trap_taken, mret_taken, trap_redirect;
  wire [31:0] trap_cause, trap_pc, trap_target;

  // 宏操作融合:融合标志沿流水传递(指令计数+2用);F5拼好的32位常数单独走一路
  wire        d_fused, d_imm_ovr_en;
  wire [31:0] d_imm_ovr;
  wire        e1_fused, e2_fused, m1_fused, w_fused;

  // 指令计数脉冲,给csr_regfile的minstret用
  reg         stall_back_prev;
  wire        instret_pulse = !stall_back_prev && w_valid;              // 写回级完成一条真指令,计数+1
  wire        instret_dbl   = w_fused;                                  // 融合指令完成时计2条

  // ==================== 3. 逻辑实现 ====================

  // -------------------- 取指 + 取指队列 --------------------
  // 一拍取两条:放了两份内容一样的指令存储器,A口读pc、B口读pc|4,相邻两条一起回来
  // BRAM是同步读,这拍给地址下拍才出数,所以取指分两步:先发地址,下拍收数进队列
  // 取回的指令先进8项的环形队列,ID每拍从队头拿1条,能融合的时候拿2条
  assign e2_is_branch_or_jump = e2_branch || e2_jump;

  wire fetch_go;                                  // 队列有余位,允许发出新取指
  wire redirect_now = predict_wrong | trap_redirect;

  // 分支目标缓冲BTB:记录"哪个地址的跳转上次跳去了哪",取指直接查表推进,命中零气泡
  // 4K项=每条指令一项;按地址位[2]拆偶奇两半,一拍查出相邻两条的表项
  // 上电全空,跳转真实发生才记录;表项错了EX2会纠正,只付误预测惩罚,不会算错
  reg  [13:0] btb_mem_e [0:2047];   // 偶槽(地址位[2]=0)
  reg  [13:0] btb_mem_o [0:2047];   // 奇槽(地址位[2]=1)
  integer bi;
  initial begin
    for (bi = 0; bi < 2048; bi = bi + 1) begin    // 上电全空(FPGA 初值)
      btb_mem_e[bi] = 14'd0;
      btb_mem_o[bi] = 14'd0;
    end
  end

  // 写口(EX2侧):分支记"跳+目标",ret只记类型(目标查返回栈),普通jalr不记(目标不定)
  // 记过"跳"的项不抹掉:循环回边重入立刻预测跳,只在退出时错一次
  wire        btb_ret   = e2_jump && (e2_instr[6:0] == 7'b110_0111) && (e2_instr[11:7] == 5'd0)
                        && ((e2_instr[19:15] == 5'd1) || (e2_instr[19:15] == 5'd5));
  wire        btb_jal   = e2_jump && (e2_instr[6:0] == 7'b110_1111);
  wire        btb_take  = (e2_branch && e2_branch_taken) || btb_jal || btb_ret;
  wire [13:0] btb_wword = btb_ret ? {2'b11, 12'd0} : {2'b10, e2_pc_target[13:2]};
  always @(posedge clk) begin
    if (btb_take && !stall_back) begin
      if (e2_pc[2]) btb_mem_o[e2_pc[13:3]] <= btb_wword;
      else          btb_mem_e[e2_pc[13:3]] <= btb_wword;
    end
  end

  // 读口(取指侧):一拍同时查出A、B两条的表项。A=pc那条,B=pc|4那条。
  // A预测跳 -> 往A的目标走,B是错路的,这拍不取B;只有B预测跳 -> 两条都取,往B的目标走。
  wire [13:0] btb_row_e = btb_mem_e[pc[13:3]];
  wire [13:0] btb_row_o = btb_mem_o[pc[13:3]];
  wire [13:0] btb_a     = pc[2] ? btb_row_o : btb_row_e;
  wire [13:0] btb_b     = btb_row_o;
  wire [31:0] btb_tgt_a = btb_a[12] ? ras_top_o : {18'b10_0000_0000_0000_0000, btb_a[11:0], 2'b00};
  wire [31:0] btb_tgt_b = btb_b[12] ? ras_top_o : {18'b10_0000_0000_0000_0000, btb_b[11:0], 2'b00};
  wire        slot_b_new = ~pc[2];
  wire        take_a    = btb_a[13];
  wire        take_b    = slot_b_new & ~take_a & btb_b[13];
  wire        issue_b   = slot_b_new & ~take_a;             // A 槽预测跳转则 B 槽为错路,不发
  wire [31:0] pc_b      = {pc[31:3], 1'b1, pc[1:0]};        // pc|4(纯位拼接,无加法器)
  wire [31:0] seq_next  = {pc[31:3] + 29'd1, 3'b000};       // 顺序推进:下一对齐组
  wire [31:0] btb_next  = take_a ? btb_tgt_a : (take_b ? btb_tgt_b : seq_next);
  // 记下各槽"实际的下一取指地址",预测对不对以后拿它来核对
  wire [31:0] succ_a    = take_a ? btb_tgt_a : (slot_b_new ? pc_b : seq_next);
  wire [31:0] succ_b    = take_b ? btb_tgt_b : seq_next;

  // 发出去的取指请求记一拍(BRAM下一拍才回数);跳转改道时作废在途的取指
  reg         fpend_a, fpend_b;         // 上一拍发出的 A/B 槽取指,数据本拍到达
  reg  [31:0] fpc_a;                    // A口发出的取指地址(没发新的时候保持旧值)
  reg         fpt_a, fpt_b;             // 发出时记下"这条被预测为跳转"
  reg  [31:0] fsucc_a, fsucc_b;         // 发出时记下"它的下一条取指地址"
  always @(posedge clk) begin
    if (rst) begin
      fpend_a <= 1'b0; fpend_b <= 1'b0; fpc_a <= 32'h8000_0000;
      fpt_a <= 1'b0; fpt_b <= 1'b0; fsucc_a <= 32'h8000_0004; fsucc_b <= 32'h8000_0008;
    end else if (redirect_now) begin
      fpend_a <= 1'b0; fpend_b <= 1'b0;   // 在途取指作废;下一拍从新目标重新取
    end else if (fetch_go) begin
      fpend_a <= 1'b1; fpend_b <= issue_b; fpc_a <= pc;
      fpt_a <= take_a; fpt_b <= take_b; fsucc_a <= succ_a; fsucc_b <= succ_b;
    end else begin
      fpend_a <= 1'b0; fpend_b <= 1'b0;   // 队列快满了,这拍不取新的
    end
  end

  // 禁止综合工具把PC选择逻辑挪进BRAM的地址寄存器，时序不收敛
  (* dont_touch = "true", keep = "true" *) wire [31:0] irom_addr_q;
  (* dont_touch = "true", keep = "true" *) wire [31:0] irom_addr2_q;
  assign irom_addr_q  = fetch_go ? pc   : fpc_a;
  assign irom_addr2_q = fetch_go ? pc_b : {fpc_a[31:3], 1'b1, fpc_a[1:0]};
  assign irom_addr    = irom_addr_q;
  assign irom_addr2   = irom_addr2_q;

  // 可融合对判定(纯组合函数;入队时绑定,消费端只读 1 位存储标志——
  // 匹配逻辑只接到队列寄存器的数据输入上,绝不掺进stall到时钟使能那条路径)
  function automatic fuse_pair_f;
    input [31:0] w1;
    input [31:0] w2;
    reg [4:0] rd1;
    reg f1m, f5m, f2m;
    begin
      rd1 = w1[11:7];
      f1m = (w1[6:0]==7'b0010011) && (w1[14:12]==3'b000) && (w1[31:20]==12'd0) && (rd1!=5'd0)
         && ((w2[6:0]==7'b0010011 && w2[19:15]==rd1 && w2[11:7]==rd1)
          || (w2[6:0]==7'b0110011 && w2[31:25]!=7'b0000001 && w2[11:7]==rd1
              && (w2[19:15]==rd1 || w2[24:20]==rd1)));
      f5m = (w1[6:0]==7'b0110111) && (rd1!=5'd0)
         && (w2[6:0]==7'b0010011) && (w2[14:12]==3'b000) && (w2[19:15]==rd1) && (w2[11:7]==rd1);
      f2m = `FUSE_F2 && (w1[6:0]==7'b0010011) && (w1[14:12]==3'b001) && (w1[31:25]==7'b0000000)
         && (w1[19:15]==rd1) && (rd1!=5'd0) && (w1[24:20]>=5'd1) && (w1[24:20]<=5'd3)
         && (w2[6:0]==7'b0110011) && (w2[14:12]==3'b000) && (w2[31:25]==7'b0000000)
         && (w2[11:7]==rd1) && ((w2[19:15]==rd1) ^ (w2[24:20]==rd1));
      fuse_pair_f = `FUSE_EN & (f1m | f5m | f2m);
    end
  endfunction

  // 取指队列:8项环形缓冲。队空时新到指令当拍可用;pc/目标只存低位字号,省寄存器
  // 关键:队列项只在入队时写,停顿只动队头指针 —— stall路径长,不能再去使能几百个寄存器
  // 深度8保证融合要看的"队头后一条"大概率已在队内
  reg  [31:0] fq_instr [0:7];
  reg  [11:0] fq_pci   [0:7];
  reg         fq_pt    [0:7];
  reg  [11:0] fq_ptgti [0:7];
  reg         fq_fuse  [0:7];   // 本项与其队内后继构成可融合对(入队时绑定)
  reg  [2:0]  fq_hp;            // 队头指针(stall 域唯一使能的状态,3 位)
  reg  [2:0]  fq_tp;            // 队尾指针(取指域使能)
  reg  [3:0]  fq_cnt;

  wire push_a = fpend_a & ~redirect_now;    // 到达数据入队(重定向当拍作废)
  wire push_b = fpend_b & ~redirect_now;
  wire [31:0] in_b_pc = {fpc_a[31:3], 1'b1, fpc_a[1:0]};

  // 融合对的判定有两种时机:同一拍到的A、B直接配;跨两次取指的
  // (上一批最后一条 配 这一批第一条)等后一条到了再补配。
  // 被预测为跳转的不配 —— 它后面那条不是真邻居。
  wire        pair_ab   = fuse_pair_f(irom_data, irom_data2) & ~fpt_a & ~fpt_b;
  wire [2:0]  fq_tpm1   = fq_tp - 3'd1;                     // 队尾前一项(晚绑的左元素)
  wire        late_bit  = fuse_pair_f(fq_instr[fq_tpm1], irom_data)
                        & ~fq_pt[fq_tpm1] & ~fpt_a;

  wire [2:0]  fq_hp1     = fq_hp + 3'd1;
  wire        head_v     = (fq_cnt != 4'd0) | push_a;
  wire [31:0] head_instr = (fq_cnt != 4'd0) ? fq_instr[fq_hp] : irom_data;
  wire [31:0] head_pc    = (fq_cnt != 4'd0) ? {18'b10_0000_0000_0000_0000, fq_pci[fq_hp], 2'b00}   : fpc_a;
  wire        head_pt    = (fq_cnt != 4'd0) ? fq_pt[fq_hp]    : fpt_a;
  wire [31:0] head_ptgt  = (fq_cnt != 4'd0) ? {18'b10_0000_0000_0000_0000, fq_ptgti[fq_hp], 2'b00} : fsucc_a;
  // ---- 宏操作融合:队头相邻两条是固定搭配就合成一条(只看编码位,与程序内容无关) ----
  // 判定只对已入队的指令做:BRAM刚出的数据不参与,否则组合路径过长时序不收敛
  wire [31:0] next_instr = fq_instr[fq_hp1];
  wire [31:0] next_ptgt  = {18'b10_0000_0000_0000_0000, fq_ptgti[fq_hp1], 2'b00};

  // F1「搬运+运算」:I1 = addi rX,rY,0(即 mv rX,rY);I2 = 普通 ALU 运算且 rd==rX、读 rX
  //   → 把 I2 的源寄存器域改写成 rY,I1 就不用执行了,两条一拍完成。数据通路不用改。
  wire [4:0]  i1_rd   = head_instr[11:7];
  wire [4:0]  i1_rs1  = head_instr[19:15];
  wire [4:0]  i2_rd   = next_instr[11:7];
  wire [4:0]  i2_rs1  = next_instr[19:15];
  wire [4:0]  i2_rs2  = next_instr[24:20];
  wire i1_is_mv    = (head_instr[6:0] == 7'b0010011) && (head_instr[14:12] == 3'b000)
                  && (head_instr[31:20] == 12'd0) && (i1_rd != 5'd0);
  wire i2_is_opimm = (next_instr[6:0] == 7'b0010011);
  wire i2_is_op    = (next_instr[6:0] == 7'b0110011) && (next_instr[31:25] != 7'b0000001);  // 排除 M 扩展(乘除另有通路)
  wire i2_rs1_hit  = (i2_rs1 == i1_rd);
  wire i2_rs2_hit  = (i2_rs2 == i1_rd) && i2_is_op;    // OP-IMM 的[24:20]是立即数/移位量,不改写
  wire [31:0] f1_word = {next_instr[31:25],
                         (i2_rs2_hit ? i1_rs1 : i2_rs2),
                         (i2_rs1_hit ? i1_rs1 : i2_rs1),
                         next_instr[14:12], next_instr[11:7], next_instr[6:0]};

  // F2「移位加」:I1 = slli rX,rX,N(N=1/2/3);I2 = add rX,{rX,rY}(恰一个源是 rX)
  //   → 改写成真实的 Zba 编码 shNadd rX,rX,rY(rs1=被移位的,rs2=另一个),I1 不用执行了。
  //   唯一触碰 ALU 数据通路的融合(A 口定值预移位),时序由实现实验裁决。
  wire i1_is_slli = (head_instr[6:0] == 7'b0010011) && (head_instr[14:12] == 3'b001)
                 && (head_instr[31:25] == 7'b0000000) && (i1_rs1 == i1_rd) && (i1_rd != 5'd0)
                 && (head_instr[24:20] >= 5'd1) && (head_instr[24:20] <= 5'd3);
  wire i2_is_add  = (next_instr[6:0] == 7'b0110011) && (next_instr[14:12] == 3'b000)
                 && (next_instr[31:25] == 7'b0000000);
  wire f2_s1 = (i2_rs1 == i1_rd);
  wire f2_s2 = (i2_rs2 == i1_rd);
  wire f2_match = `FUSE_F2 & i1_is_slli & i2_is_add & (i2_rd == i1_rd) & (f2_s1 ^ f2_s2);
  wire [2:0]  f2_f3   = {head_instr[21:20], 1'b0};   // shamt 1/2/3 → funct3 010/100/110
  wire [31:0] f2_word = {7'b0010000, (f2_s1 ? i2_rs2 : i2_rs1), i1_rd, f2_f3, i1_rd, 7'b0110011};

  // F5「装常数」:I1 = lui rX,hi;I2 = addi rX,rX,lo → 保留 LUI 词形(ALU 直通 B 口),
  //   32 位常数在此处(队头寄存器之后、译码之前)预先算成 hi+lo,不占执行级时序。
  wire f5_match = (head_instr[6:0] == 7'b0110111) && (i1_rd != 5'd0)
               && (next_instr[6:0] == 7'b0010011) && (next_instr[14:12] == 3'b000)
               && (i2_rs1 == i1_rd) && (i2_rd == i1_rd);
  wire [31:0] f5_imm = {head_instr[31:12], 12'd0} + {{20{next_instr[31]}}, next_instr[31:20]};

  // 安全条件:两条都未被预测为跳转(否则第二条不是真邻居);两条同进同退,没有半对状态
  wire fuse_pat = (fq_cnt != 4'd0) & fq_fuse[fq_hp];

  wire        pop1       = head_v & ~stall & ~redirect_now;
  wire [1:0]  pop_n      = pop1 ? (fuse_pat ? 2'd2 : 2'd1) : 2'd0;

  // 队列快满就别再取:算上在途还没到的,队里还得装得下新取的一对才行
  assign fetch_go = ({1'b0, fq_cnt} + {4'b0, fpend_a} + {4'b0, fpend_b}) <= 5'd6;

  always @(posedge clk) begin
    if (rst | redirect_now) fq_cnt <= 4'd0;
    else fq_cnt <= fq_cnt + {3'b0, push_a} + {3'b0, push_b} - {2'b0, pop_n};
  end
  // 队头指针:停顿信号只需要管住这3位(环形队列,加过头自动回卷)
  always @(posedge clk) begin
    if (rst | redirect_now) fq_hp <= 3'd0;
    else fq_hp <= fq_hp + {1'b0, pop_n};
  end
  // 队尾指针:取指域使能,不含 stall
  always @(posedge clk) begin
    if (rst | redirect_now) fq_tp <= 3'd0;
    else if (push_a) fq_tp <= fq_tp + (push_b ? 3'd2 : 3'd1);
  end
  // 各项只在入队时写,写使能仅由"新指令到达且写指针指向本项"决定,与停顿信号无关
  genvar qi;
  generate
    for (qi = 0; qi < 8; qi = qi + 1) begin : g_fq
      always @(posedge clk) begin
        if (push_a && (fq_tp == qi[2:0])) begin
          fq_instr[qi] <= irom_data;   fq_pci[qi]   <= fpc_a[13:2];
          fq_pt[qi]    <= fpt_a;       fq_ptgti[qi] <= fsucc_a[13:2];
          fq_fuse[qi]  <= push_b & pair_ab;          // 组内配对(B 同拍在场才可能)
        end else if (push_b && ((fq_tp + 3'd1) == qi[2:0])) begin
          fq_instr[qi] <= irom_data2;  fq_pci[qi]   <= in_b_pc[13:2];
          fq_pt[qi]    <= fpt_b;       fq_ptgti[qi] <= fsucc_b[13:2];
          fq_fuse[qi]  <= 1'b0;                      // 后继未到,待下组晚绑
        end
        // 跨组晚绑:队尾前一项(仍在队中)对本组 A;地址与上面两支不重叠
        if (push_a && (fq_cnt != 4'd0) && (fq_tpm1 == qi[2:0]))
          fq_fuse[qi] <= late_bit;
      end
    end
  endgenerate

  // 消费端(队头 → 译码):空队/被重定向时给 NOP 气泡;融合时送改写后的熔合词
  wire        do_fuse    = fuse_pat & head_v;
  // 队头的 fuse 位在入队时就绑定了(f1|f2|f5 三选一),所以既非 f5 又非 f2 时必是 f1。
  wire [31:0] fused_word = f5_match ? head_instr : (f2_match ? f2_word : f1_word);
  wire [31:0] if_instr   = ~head_v ? 32'h00000013 : (do_fuse ? fused_word : head_instr);
  wire [31:0] head_pc4   = head_pc + (do_fuse ? 32'd8 : 32'd4);  // 熔合操作占两条指令的地址跨度
  assign predict_taken   = head_pt & head_v;                     // 融合时恒 0(fuse_pat 已保证)
  assign predict_target  = do_fuse ? next_ptgt : head_ptgt;      // 融合对的"实际下一址"=第二条的记录

  // 只剩返回地址栈:方向/目标预测由取指队列里预译码好的 head_pt/head_ptgt 给出
  ras u_ras (
      .clk          (clk),
      .rst          (rst),
      .stall_back   (stall_back),
      .ex_is_branch (e2_is_branch_or_jump),
      .ex_instr_type(e2_instr_type),
      .ex_pc        (e2_pc),
      .ras_top_o    (ras_top_o)
  );

  pc_reg u_pc_reg (
      .clk(clk),
      .rst(rst),
      .stall(~fetch_go),          // 队列快满才冻结PC;流水线停顿由队列存货顶着,不用停取指
      .redirect(redirect_now),    // EX2预测错/异常时强制改PC(比队列满优先)
      .pc_next(pc_next),          // 含 predict_taken 目标(正常推进时生效)
      .pc(pc)
  );

  if_id_reg u_if_id_reg (
      .clk(clk),
      .rst(rst),
      .flush(flush_if_id),
      .stall(stall),
      .pc_in(head_pc),
      .pc4_in(head_pc4),
      .instr_in(if_instr),
      .predict_taken_in(predict_taken),
      .predict_target_in(predict_target),
      .fused_in(do_fuse),
      .valid_in(head_v),
      .imm_ovr_in(f5_imm),
      .imm_ovr_en_in(do_fuse & f5_match),
      .d_fused(d_fused),
      .d_imm_ovr(d_imm_ovr),
      .d_imm_ovr_en(d_imm_ovr_en),
      .d_pc(d_pc),
      .d_pc4(d_pc4),
      .d_instr(d_instr),
      .d_predict_taken(d_predict_taken),
      .d_predict_target(d_predict_target),
      .d_valid(d_valid)
  );

  // -------------------- ID --------------------
  assign rs1_addr  = d_instr[19:15];
  assign rs2_addr  = d_instr[24:20];
  assign rd_addr_d = d_instr[11:7];

  regfile u_regfile (
      .clk(clk),
      .rs1_addr(rs1_addr),
      .rs2_addr(rs2_addr),
      .rd_addr(w_rd_addr),
      .wd(wb_data),
      .reg_we(w_reg_we),
      .rs1_rf(rs1_rf),
      .rs2_rf(rs2_rf)
  );

  wire wb_bypass_rs1 = w_reg_we && (w_rd_addr != 5'd0) && (w_rd_addr == rs1_addr);
  wire wb_bypass_rs2 = w_reg_we && (w_rd_addr != 5'd0) && (w_rd_addr == rs2_addr);
  wire [31:0] rs1_rf_final = wb_bypass_rs1 ? wb_data : rs1_rf;
  wire [31:0] rs2_rf_final = wb_bypass_rs2 ? wb_data : rs2_rf;

  imm_gen u_imm_gen (
      .d_instr(d_instr),
      .imm(imm)
  );

  // F5 融合:32 位合成常数已在取指队列头算好,此处仅一层选择进执行流水
  wire [31:0] imm_eff = d_imm_ovr_en ? d_imm_ovr : imm;

  ctrl u_ctrl (
      .d_instr(d_instr),
      .reg_we_d(reg_we_d),
      .mem_we_d(mem_we_d),
      .mem_re_d(mem_re_d),
      .branch_d(branch_d),
      .jump_d(jump_d),
      .alu_src_d(alu_src_d),
      .rs1_en_d(rs1_en_d),
      .rs2_en_d(rs2_en_d),
      .wb_sel_d(wb_sel_d),
      .alu_op_d(alu_op_d),
      .mem_width_d(mem_width_d),
      .mem_sign_d(mem_sign_d),
      .instr_type_d(d_instr_type),
      .is_csr_d(is_csr_d),
      .csr_op_d(csr_op_d),
      .csr_uimm_d(csr_uimm_d),
      .is_ecall_d(is_ecall_d),
      .is_mret_d(is_mret_d),
      .is_mul_d(is_mul_d),
      .is_div_d(is_div_d),
      .use_pc_d(use_pc_d)
  );

  id_ex1_reg u_id_ex1_reg (
      .clk(clk),
      .rst(rst),
      .flush(flush_id_ex1),
      .stall(stall),
      .pc_in(d_pc),
      .pc4_in(d_pc4),
      .instr_in(d_instr),
      .rs1_in(rs1_rf_final),
      .rs2_in(rs2_rf_final),
      .imm_in(imm_eff),
      .rd_addr_in(rd_addr_d),
      .reg_we_in(reg_we_d),
      .mem_we_in(mem_we_d),
      .mem_re_in(mem_re_d),
      .branch_in(branch_d),
      .jump_in(jump_d),
      .alu_src_in(alu_src_d),
      .wb_sel_in(wb_sel_d),
      .alu_op_in(alu_op_d),
      .mem_width_in(mem_width_d),
      .mem_sign_in(mem_sign_d),
      .predict_taken_in(d_predict_taken),
      .predict_target_in(d_predict_target),
      .instr_type_in(d_instr_type),
      .is_csr_in(is_csr_d), //新增输入信号
      .csr_op_in(csr_op_d),
      .csr_uimm_in(csr_uimm_d),
      .is_ecall_in(is_ecall_d),
      .is_mret_in(is_mret_d),
      .is_mul_in(is_mul_d),
      .is_div_in(is_div_d),
      .use_pc_in(use_pc_d),     // alu_a 选 PC 预译码，打拍到 EX1
      .fwd_a_in(fwd_a_pre),     // 在 ID 就算好的转发编码，打拍到 EX1
      .fwd_b_in(fwd_b_pre),
      .fused_in(d_fused),
      .valid_in(d_valid),
      .e1_pc(e1_pc),
      .e1_pc4(e1_pc4),
      .e1_instr(e1_instr),
      .e1_rs1(e1_rs1),
      .e1_rs2(e1_rs2),
      .e1_imm(e1_imm),
      .e1_rd_addr(e1_rd_addr),
      .e1_reg_we(e1_reg_we),
      .e1_mem_we(e1_mem_we),
      .e1_mem_re(e1_mem_re),
      .e1_branch(e1_branch),
      .e1_jump(e1_jump),
      .e1_alu_src(e1_alu_src),
      .e1_mem_sign(e1_mem_sign),
      .e1_wb_sel(e1_wb_sel),
      .e1_alu_op(e1_alu_op),
      .e1_mem_width(e1_mem_width),
      .e1_predict_taken(e1_predict_taken),
      .e1_predict_target(e1_predict_target),
      .e1_instr_type(e1_instr_type),
      .e1_is_csr(e1_is_csr),    //新增输出信号
      .e1_csr_op(e1_csr_op),
      .e1_csr_uimm(e1_csr_uimm),
      .e1_is_ecall(e1_is_ecall),
      .e1_is_mret(e1_is_mret),
      .e1_is_mul(e1_is_mul),
      .e1_is_div(e1_is_div),
      .e1_use_pc(e1_use_pc),
      .e1_fwd_a(e1_fwd_a),
      .e1_fwd_b(e1_fwd_b),
      .e1_fused(e1_fused),
      .e1_valid(e1_valid)
  );

  // -------------------- EX1 --------------------
  // 转发时序原则:多路选择器每一路都必须是寄存器直接输出,EX1只剩"寄存器->选择器->ALU";
  // 做不到直连的(如MEM1一路要五选一),提前一拍选好寄存,见下面的预选寄存器。

  // MEM1预选转发寄存器:指令从EX2进MEM1时,把"后续指令要转发的值"五选一先存好
  // (缓冲命中/直传/投机读/pc+4/ALU结果),下一拍EX1直接取,零组合逻辑。
`ifdef SUBWORD_FAST
  // 子字load的车道提取+扩展(word原样直通)。两处捕获点(mem1_fwd_reg/d1_data_reg)共用;
  // 宽度/符号/车道选择全是寄存器输出,数据路径只多约两级选择。
  function [31:0] ld_fmt(input [31:0] w, input [1:0] width, input sgn, input [1:0] lane);
    reg [7:0]  fb;
    reg [15:0] fh;
    begin
      fb = (lane == 2'd0) ? w[7:0]   : (lane == 2'd1) ? w[15:8] :
           (lane == 2'd2) ? w[23:16] : w[31:24];
      fh = lane[1] ? w[31:16] : w[15:0];
      ld_fmt = (width == `MEM_BYTE) ? (sgn ? {{24{fb[7]}},  fb} : {24'd0, fb}) :
               (width == `MEM_HALF) ? (sgn ? {{16{fh[15]}}, fh} : {16'd0, fh}) : w;
    end
  endfunction
`endif

  reg [31:0] mem1_fwd_reg;
  wire [31:0] mem1_fwd_pre =
`ifdef SUBWORD_FAST
                  // d1命中接力放最高优先:已格式化数据寄存器→寄存器,零时序压力。
                  // 正确性由d1捕获拍的新鲜度守卫背书(在途同址store当时就判了miss)。
                  e2_d1_ld ? d1_data_reg :
`endif
                  e2_sb_hit ? sb_ld_data :
                  e2_st2ld_fwd  ? m1_rs2 :
                  e2_spec_rd_hit ? perip_rdram :          // 投机读:数据这一拍正从 DRAM 读口到达,直接捕获
                  (e2_wb_sel == `WB_PC4) ? e2_pc4 : e2_alu_out;
  always @(posedge clk) begin
    if (rst) mem1_fwd_reg <= 32'h0;
    else if (!stall_back)
`ifdef SUBWORD_SPEC
      // 全功能版:子字load在捕获点完成车道提取+扩展(车道取真实地址e2_alu_out[1:0])。
      // 代价:格式化两级叠在douta之后,关键路径+0.25ns;时序敏感时关SUBWORD_SPEC走d1-only。
      // d1接力拍跳过fmt:d1_data_reg已格式化,二次提取会取错车道。
      mem1_fwd_reg <= (e2_mem_re && !e2_d1_ld) ? ld_fmt(mem1_fwd_pre, e2_mem_width, e2_mem_sign, e2_alu_out[1:0])
                                : mem1_fwd_pre;
`else
      // d1-only/旧行为:这条腿只装word数据,原样捕获,douta路径保持老剖面
      mem1_fwd_reg <= mem1_fwd_pre;
`endif
  end

  // (写回级的值已在w_*流水线寄存器中,多路选择器直接取用,无需再设一路)

  // jal/jalr的返回地址(pc+4)和"EX1提前查表命中的load数据"共用选择器同一路:
  //   两种指令不会同时出现,用"EX2是不是load"区分这一路此刻给哪个值。
  wire [31:0] ex2p_leg = e2_mem_re ? d1_data_reg : e2_pc4;

  wire [31:0] alu_a_fwd = (e1_fwd_a == `FWD_EX2)   ? e2_alu_out :
                          (e1_fwd_a == `FWD_EX2P)  ? ex2p_leg :
                          (e1_fwd_a == `FWD_MEM1)  ? mem1_fwd_reg :
                          (e1_fwd_a == `FWD_WB_ALU)  ? w_alu_out :
                          (e1_fwd_a == `FWD_WB_MEM) ? w_mem_rdata :
                          (e1_fwd_a == `FWD_WB_PC4)   ? w_pc4 : e1_rs1;   // (写回级已合并,无独立写回腿)

  wire [31:0] alu_b_fwd = (e1_fwd_b == `FWD_EX2)   ? e2_alu_out :
                          (e1_fwd_b == `FWD_EX2P)  ? ex2p_leg :
                          (e1_fwd_b == `FWD_MEM1)  ? mem1_fwd_reg :
                          (e1_fwd_b == `FWD_WB_ALU)  ? w_alu_out :
                          (e1_fwd_b == `FWD_WB_MEM) ? w_mem_rdata :
                          (e1_fwd_b == `FWD_WB_PC4)   ? w_pc4 : e1_rs2;   // (写回级已合并,无独立写回腿)


  // "A口用PC还是用寄存器值"在ID就判好、打一拍带过来(e1_use_pc),
  // EX1只剩一个现成的1位信号驱动选择器,不用现场认指令。
  wire [31:0] alu_a = e1_use_pc ? e1_pc : alu_a_fwd;

  // B口只选立即数或rs2。CSR的旧值不从这里进(CSR读慢,塞进ALU输入拖时序),
  // 它绕到ALU之后再并进结果,见下面alu_out那行。
  wire [31:0] alu_b = e1_alu_src ? e1_imm : alu_b_fwd;

  // CSR 写入数据：选源（rs1 或 uimm），再按 op 合成
  wire [31:0] csr_src = e1_csr_uimm ? e1_imm : alu_a_fwd;
  wire [31:0] csr_wdata = (e1_csr_op == `CSR_OP_RW) ? csr_src :
                          (e1_csr_op == `CSR_OP_RS) ? (csr_rdata | csr_src) :
                          (e1_csr_op == `CSR_OP_RC) ? (csr_rdata & ~csr_src) : 32'h0;
  // RS/RC 且源为 0 时不写；DRAM 停顿时也不写，避免 rd 取到新值；
  // 错误分支路径上的 CSR 指令也不能 commit
  wire        csr_we_real = e1_is_csr && !stall_back && !predict_wrong &&
                            !((e1_csr_op == `CSR_OP_RS || e1_csr_op == `CSR_OP_RC) &&
                              csr_src == 32'h0);

  // CSR写延后一拍提交:先落寄存器再写CSR堆,长路径拆成两拍;
  // 紧跟的CSR/mret/ecall有互锁停顿等它写完,保证读到新值。
  reg         csrw_we_r;
  reg  [11:0] csrw_addr_r;
  reg  [31:0] csrw_data_r;
  always @(posedge clk) begin
    if (rst) begin
      csrw_we_r <= 1'b0;
    end else if (!stall_back) begin
      csrw_we_r   <= csr_we_real;
      csrw_addr_r <= e1_instr[31:20];
      csrw_data_r <= csr_wdata;
    end
  end

  wire [31:0] alu_raw;
  alu u_alu (
      .alu_a(alu_a),
      .alu_b(alu_b),
      .alu_op(e1_alu_op),
      .alu_out(alu_raw)
  );

    // ---------------- MDU(除法单元) ----------------
  // 乘法已单独流水化(见下方 pmul),这里的多拍状态机只负责除法/取余。
  wire        mdu_is_op = e1_is_div;
  wire        mdu_busy, mdu_done;
  wire [31:0] mdu_result;
  reg         mdu_started;      // mdu 已经为当前 EX1 指令启动过
  reg         mdu_done_held;    // mdu_done 是 1 拍脉冲，dram_stall 时拓宽

  wire        mdu_finished = mdu_done | mdu_done_held;
  wire        mdu_start    = mdu_is_op & ~mdu_busy & ~mdu_started & ~mdu_finished;
  // mdu_stall=1 时：id_ex1_reg 持有除法指令、ex1_ex2_reg 插泡
  wire        mdu_stall = mdu_start | (mdu_started & ~mdu_finished);

  always @(posedge clk) begin
    if (rst | predict_wrong | trap_redirect) begin
      mdu_started   <= 1'b0;
      mdu_done_held <= 1'b0;
    end else begin
      // mdu_started：发 start 那拍置 1，mdu_done 一拍后清 0
      if (mdu_start) mdu_started <= 1'b1;
      else if (mdu_done) mdu_started <= 1'b0;
      // mdu_done_held:仅当 done 与 dram_stall 同拍出现时才需要拓宽;
      // ~stall_back 时立刻清 0，避免下一条紧邻的除法起不来
      if (mdu_done & stall_back) mdu_done_held <= 1'b1;
      else if (~stall_back)      mdu_done_held <= 1'b0;
    end
  end

 mdu u_mdu (
      .clk(clk),
      .rst(rst),
      .start(mdu_start),
      .alu_op(e1_alu_op),
      .a(alu_a_fwd),
      .b(alu_b_fwd),
      .flush(predict_wrong | trap_redirect),
      .busy(mdu_busy),
      .done(mdu_done),
      .result(mdu_result)
  );
    // ALU 最终输出:除法走 mdu_result;CSR 指令把旧值(csr_rdata)在此送回;其它走 alu_raw。
  // (乘法此拍还没算完,这里的值无效——真值两拍后在 MEM1 末并入结果通路,
  //  中途各级不转发乘法结果,由转发单元的排除项保证。)
  assign alu_out = mdu_is_op ? mdu_result : (e1_is_csr ? csr_rdata : alu_raw);

  // 流水化乘法,3拍出结果(原理见pmul.v)
  // 结果和load一样晚一拍才能用,停顿/转发都按load的规则处理
  // 乘完的结果在mem_wb_reg入口处并进写回通路

  pmul u_pmul (
      .clk        (clk),
      .rst        (rst),
      .stall_back (stall_back),
      .flush      (predict_wrong | trap_redirect | mdu_stall),
      .e1_is_mul  (e1_is_mul),
      .e1_alu_op  (e1_alu_op),
      .e1_a       (alu_a_fwd),
      .e1_b       (alu_b_fwd),
      .e2_is_pmul (e2_is_pmul),
      .m1_is_pmul (m1_is_pmul),
      .pmul_out   (pmul_out)
  );

  branch_comp u_branch_comp (
      .rs1_bc(alu_a_fwd),
      .rs2_bc(alu_b_fwd),
      .funct3_d(e1_instr[14:12]),
      .is_branch(e1_branch),
      .branch_taken(branch_taken)
  );


   // CSR 寄存器堆
  csr_regfile u_csr_regfile (
      .clk(clk),
      .rst(rst),
      .csr_we(csrw_we_r),
      .csr_addr(e1_instr[31:20]),
      .csr_waddr(csrw_addr_r),
      .csr_wdata(csrw_data_r),
      .csr_rdata(csr_rdata),
      .trap_taken(trap_taken),
      .trap_pc(trap_pc),
      .trap_cause(trap_cause),
      .mret_taken(mret_taken),
      .instret_inc(instret_pulse),
      .instret_dbl(instret_dbl),
      .mtvec_o(mtvec_o),
      .mepc_o(mepc_o)
  );

  // Trap 控制
  trap_ctrl u_trap_ctrl (
      .e1_is_ecall(e1_is_ecall),
      .e1_is_mret(e1_is_mret),
      .e1_pc(e1_pc),
      .stall_back(stall_back),
      .predict_wrong(predict_wrong),
      .mtvec(mtvec_o),
      .mepc(mepc_o),
      .trap_taken(trap_taken),
      .mret_taken(mret_taken),
      .trap_cause(trap_cause),
      .trap_pc(trap_pc),
      .trap_redirect(trap_redirect),
      .trap_target(trap_target)
  );

  ex1_ex2_reg u_ex1_ex2_reg (
      .clk(clk),
      .rst(rst),
      .flush(predict_wrong | trap_redirect | mdu_stall),  // 除法多周期时插泡；预测错冲刷EX1/EX2错路指令
      .stall(stall_back),
      .pc_in(e1_pc),
      .pc4_in(e1_pc4),
      .instr_in(e1_instr),
      .rs2_in(alu_b_fwd),       // store 数据：含 store-buffer 命中转发
      .alu_out_in(alu_out),
      .branch_taken_in(branch_taken),
      .rd_addr_in(e1_rd_addr),
      .reg_we_in(e1_reg_we),
      .mem_we_in(e1_mem_we),
      .mem_re_in(e1_mem_re),
      .branch_in(e1_branch),
      .jump_in(e1_jump),
      .mem_sign_in(e1_mem_sign),
      .wb_sel_in(e1_wb_sel),
      .mem_width_in(e1_mem_width),
      .predict_taken_in(e1_predict_taken),
      .predict_target_in(e1_predict_target),
      .instr_type_in(e1_instr_type),
      .fused_in(e1_fused),
      .valid_in(e1_valid),
      .e2_pc(e2_pc),
      .e2_pc4(e2_pc4),
      .e2_instr(e2_instr),
      .e2_rs2(e2_rs2),
      .e2_alu_out(e2_alu_out),
      .e2_branch_taken(e2_branch_taken),
      .e2_rd_addr(e2_rd_addr),
      .e2_reg_we(e2_reg_we),
      .e2_mem_we(e2_mem_we),
      .e2_mem_re(e2_mem_re),
      .e2_branch(e2_branch),
      .e2_jump(e2_jump),
      .e2_mem_sign(e2_mem_sign),
      .e2_wb_sel(e2_wb_sel),
      .e2_mem_width(e2_mem_width),
      .e2_predict_taken(e2_predict_taken),
      .e2_predict_target(e2_predict_target),
      .e2_instr_type(e2_instr_type),
      .e2_fused(e2_fused),
      .e2_valid(e2_valid)
  );

  // -------------------- EX2 --------------------
  assign e2_pc_sel = ((e2_branch & e2_branch_taken) | e2_jump) & ~stall_back;
  // 跳转目标就是EX1算好的alu结果(分支=pc+imm,jalr=rs1+imm);jalr按规范把最低位清0
  assign e2_pc_target = (e2_instr[6:0] == 7'b110_0111) ? {e2_alu_out[31:1], 1'b0} : e2_alu_out;

  // PC 选择,优先级:异常/中断 > 误预测纠正 > 查表推进。
  // 查表把"预测跳转的目标"和"顺序下一条"并成了一个出口,预测跳转不再有
  // "取到指令→识别是跳转→改向"的一拍气泡。
  assign pc_next = trap_redirect ? trap_target :
                   predict_wrong ? (e2_pc_sel ? e2_pc_target : e2_pc4) :
                   btb_next;

  ex2_mem1_reg u_ex2_mem1_reg (
      .clk(clk),
      .rst(rst),
      .stall(stall_back),
      .pc4_in(e2_pc4),
      .instr_in(e2_instr),
      .alu_out_in(e2_alu_out),
      .rs2_in(e2_rs2),
      .rd_addr_in(e2_rd_addr),
      .reg_we_in(e2_reg_we),
      .mem_we_in(e2_mem_we),
      .mem_re_in(e2_mem_re),
      .mem_sign_in(e2_mem_sign),
      .wb_sel_in(e2_wb_sel),
      .mem_width_in(e2_mem_width),
      .fused_in(e2_fused),
      .valid_in(e2_valid),
      .m1_pc4(m1_pc4),
      .m1_instr(m1_instr),
      .m1_alu_out(m1_alu_out),
      .m1_rs2(m1_rs2),
      .m1_rd_addr(m1_rd_addr),
      .m1_reg_we(m1_reg_we),
      .m1_mem_we(m1_mem_we),
      .m1_mem_re(m1_mem_re),
      .m1_mem_sign(m1_mem_sign),
      .m1_wb_sel(m1_wb_sel),
      .m1_mem_width(m1_mem_width),
      .m1_fused(m1_fused),
      .m1_valid(m1_valid)
  );

  // -------------------- MEM1(访存) --------------------
  // 数据存储器双口:A口只写,B口只读,地址独立;load地址提前送B口,读延迟藏进流水线
  // 两种情况放弃提前读退回普通路径(少省一拍但保证正确):B口被占(dram_stall)/
  // 同拍store写同地址(先写后读拿旧值)。不做范围检查:读到无效地址的数据后面不会被用
  wire        st_conflict    = m1_mem_we && (m1_alu_out[17:2] == e2_alu_out[17:2]);

  // ---- 投机读:整字load的地址在ID预测好,EX1就发读口,数据EX2到,后续指令零等待 ----
  // 四种情况不发(让给普通路径,只慢不错):EX2的load在用读口/store要写同地址/读口被占/冻结
`ifdef SUBWORD_FAST
`ifndef SUBWORD_SPEC
  // d1-only配置:子字load不发投机读(地址预算/车道/查表照旧),douta路径退回老剖面
  wire spec_w_ok = (e1_mem_width == `MEM_WORD);
`else
  wire spec_w_ok = 1'b1;                       // 全功能:子字也发投机读
`endif
`else
  wire spec_w_ok = 1'b1;                       // 旧行为:spec_addr_valid本身已是word-only
`endif
  wire spec_rd_issue = spec_addr_valid && spec_w_ok               // 地址已在译码级预算好并落寄存器,类型/范围也已验过
               && !(e2_mem_re && !e2_spec_rd_hit)          // EX2的load占着读口就让 —— 除非它自己是投机读命中(不占口),连环load可都走投机
               && !e2_mem_we
               && !(m1_mem_we && dram_range)          // MEM1 store 本拍提交=同边沿写读碰撞(READ_FIRST 读旧),保守挡
               && !dram_stall;
  reg  e2_spec_rd, m1_spec_rd;
  always @(posedge clk) begin
    if (rst) e2_spec_rd <= 1'b0;
    else if (!stall_back) begin
      if (predict_wrong | trap_redirect | mdu_stall) e2_spec_rd <= 1'b0;
      else e2_spec_rd <= spec_rd_issue;
    end
  end
  assign e2_spec_rd_hit = e2_spec_rd;   // 地址范围在ID已经验过,发出去就算命中,不再二次检查
  always @(posedge clk) begin
    if (rst) m1_spec_rd <= 1'b0;
    else if (!stall_back) m1_spec_rd <= e2_spec_rd_hit;
  end

  wire        ex2_rd_issue     = e2_mem_re && !e2_spec_rd_hit && !dram_stall && !st_conflict;
  // m1_ex2_rd 已在顶部前向声明
  wire [1:0]  dram_need      = (m1_ex2_rd || m1_spec_rd || m1_st2ld_fwd) ? 2'd0 : 2'd1;   // 数据存储器读延迟 1 拍(IP 无输出寄存器)。
                                                         //  普通读停 1 拍;投机读/提前读已提前送出地址,停 0 拍。
                                                         //  仿真模型与 IP 同为 1 拍读延迟,行为一致。

  // 写口/MMIO 地址恒为 MEM1 地址:纯寄存器源,不带选择逻辑。
  assign perip_addr  = m1_alu_out;
  // 读口地址三选一:EX1 投机读(预测地址)> EX2 提前读(真实地址)> MEM1 补读
  assign perip_raddr = spec_rd_issue ? {14'h2004, spec_ld_waddr, 2'b00} : ex2_rd_issue ? e2_alu_out : m1_alu_out;
  assign perip_wen   = m1_mem_we;     // 写只来自 MEM1
  assign perip_mask  = m1_mem_width;
  assign perip_wdata = m1_rs2;

  assign dram_range  = (m1_alu_out[31:18] == 14'h2004);  // MEM1的地址落在DRAM区(0x8010_0000起256KB)?
  assign dram_stall  = m1_mem_re && dram_range && (dram_wait_cnt < dram_need);
  assign stall_back  = dram_stall;

  always @(posedge clk) begin
    if (rst) dram_wait_cnt <= 2'd0;
    else if (m1_mem_re && dram_range && dram_wait_cnt < dram_need) dram_wait_cnt <= dram_wait_cnt + 2'd1;
    else if (!stall_back) dram_wait_cnt <= 2'd0;
  end

  // m1_ex2_rd 与 load 一起从 EX2 推进到 MEM1（与 ex2_mem1_reg 同步，停顿时保持）
  always @(posedge clk) begin
    if (rst) m1_ex2_rd <= 1'b0;
    else if (!stall_back) m1_ex2_rd <= ex2_rd_issue;
  end

  // 投机读的仿真自检(硬件不校验,地址算错=静默拿错数据);只存在于仿真,综合自动剪除
  // synthesis translate_off
  reg [15:0] chk_e2_waddr, chk_m1_waddr;   // 预算地址随 load 走到 MEM1
`ifdef SUBWORD_FAST
  reg [1:0]  chk_e2_lane,  chk_m1_lane;    // 预测车道随 load 走到 MEM1(A1b 用)
`endif
  always @(posedge clk) begin
    if (!stall_back) begin
      chk_e2_waddr <= spec_ld_waddr;
      chk_m1_waddr <= chk_e2_waddr;
`ifdef SUBWORD_FAST
      chk_e2_lane  <= spec_ld_lane;
      chk_m1_lane  <= chk_e2_lane;
`endif
    end
  end
  always @(posedge clk) begin
    if (!rst && m1_spec_rd && m1_mem_re && !dram_stall) begin
      // A1:投机读命中 ⇒ 预测地址 == EX1 真正算出的地址
      if (chk_m1_waddr !== m1_alu_out[17:2]) begin
        $display("[ASSERT-A1 FAIL] t=%0t 投机读地址失配:预测=%04x 真实=%04x (m1_alu_out=%08x)",
                 $time, chk_m1_waddr, m1_alu_out[17:2], m1_alu_out);
        $fatal(1);
      end
`ifdef SUBWORD_FAST
      // A1b:预测车道 == 真实地址低 2 位(d1 捕获用预测车道做提取,靠这条兜底)
      if (chk_m1_lane !== m1_alu_out[1:0]) begin
        $display("[ASSERT-A1b FAIL] t=%0t 投机读车道失配:预测=%b 真实=%b (m1_alu_out=%08x)",
                 $time, chk_m1_lane, m1_alu_out[1:0], m1_alu_out);
        $fatal(1);
      end
`endif
      // A2:投机读命中 ⇒ 该 load 的真实地址在 DRAM 窗口内
      if (m1_alu_out[31:18] !== 14'h2004) begin
        $display("[ASSERT-A2 FAIL] t=%0t 投机读的 load 真实地址不在 DRAM 窗口: %08x",
                 $time, m1_alu_out);
        $fatal(1);
      end
    end
  end
  // synthesis translate_on

  // store_buffer:记录最近写过的字,EX2查表命中就提前一拍转发、提前放行后续指令
  // (原理见store_buffer.v;写回值仍取存储器,同拍在写的按未命中处理)
  // ---- ID提前算load地址:基址+偏移在译码级算好,寄存后给EX1发投机读用 ----
  // 基址按转发选择取;拿不到确定值就放弃,该load走普通路径。地址先寄存再用(要驱动几十片BRAM)
  // spec_base_ok是基址可信检查 —— 这里出过大bug,务必小心:有些情况转发码匹配但值不是基址,
  // 如前一条是load(e2_alu_out是它的访存地址,不是数据,连环指针p=p->next即此)或jal(是返回地址),
  // 这些一律放弃预测:宁可慢一拍,不能拿错地址读存储器
  wire        spec_base_ok = (fwd_a_pre == `FWD_NONE)
                       || (fwd_a_pre == `FWD_EX2  && !e1_is_csr && !e1_is_div)
                       || (fwd_a_pre == `FWD_MEM1 && !e2_mem_re && (e2_wb_sel != `WB_PC4))
                       || (fwd_a_pre == `FWD_WB_ALU);
  wire [31:0] spec_base = (fwd_a_pre == `FWD_EX2)   ? alu_raw :
                       (fwd_a_pre == `FWD_MEM1)  ? e2_alu_out :
                       (fwd_a_pre == `FWD_WB_ALU)  ? m1_alu_out : rs1_rf_final;
  // 两个省时序的招:范围检查直接看基址(不等加法结果,两件事并行做);
  // 加法只算低18位(反正只要字地址)。基址在存储器边界2KB内的都保守放弃,防止加完越界
`ifdef SUBWORD_FAST
  // 子字load同样预算地址(读口永远按字对齐发读,车道另存spec_ld_lane)
  wire        spec_ld_cand = mem_re_d && spec_base_ok;
`else
  wire        spec_ld_cand = mem_re_d && (mem_width_d == `MEM_WORD) && spec_base_ok;
`endif
  wire [17:0] spec_addr18  = spec_base[17:0] + imm[17:0];
  wire        spec_base_in_dram = (spec_base[31:18] == 14'h2004)
                         && (spec_base[17:11] != 7'h7F) && (spec_base[17:11] != 7'h00);
  // (spec_addr_valid/spec_ld_waddr/spec_ld_lane 顶部前向声明;范围检查已并入 spec_addr_valid)
  always @(posedge clk) begin
    if (rst) begin
      spec_addr_valid <= 1'b0; spec_ld_waddr <= 16'h0;
`ifdef SUBWORD_FAST
      spec_ld_lane <= 2'b0;
`endif
    end else if (flush_id_ex1) begin        // 与 u_id_ex1_reg 同语义:flush 优先于 stall
      spec_addr_valid <= 1'b0;
    end else if (!stall) begin
      spec_addr_valid   <= spec_ld_cand && spec_base_in_dram;   // 范围与加法并行预验(见上)
      spec_ld_waddr  <= spec_addr18[17:2];
`ifdef SUBWORD_FAST
      spec_ld_lane   <= spec_addr18[1:0];
`endif
    end
  end
  wire        d1_sb_hit;
  wire [31:0] d1_sb_data;

  assign      e2_sb_range = (e2_alu_out[31:18] == 14'h2004);  // EX2的地址落在DRAM区?(高14位等值比较)
  wire        sb_ld_hit;
  // sb_ld_data / e2_sb_hit 已在顶部前向声明(EX1 段 mem1_fwd_reg 引用)
  // 只放4项就够:比较逻辑串在停顿判断的路径上,项越少越快;
  // 程序热点就内层循环那三四个栈槽,4项和8项命中率几乎一样。
`ifdef SUBWORD_FAST
  // 子字store车道对齐:数据按道复制、掩码标写到的字节(与BRAM字节使能写同语义,
  // 缓冲字节与存储器逐字节一致)。load侧生成"需要哪些字节"的需求掩码。
  wire [3:0]  sb_st_mask  = (m1_mem_width == `MEM_WORD) ? 4'b1111 :
                            (m1_mem_width == `MEM_HALF) ? (m1_alu_out[1] ? 4'b1100 : 4'b0011) :
                                                          (4'b0001 << m1_alu_out[1:0]);
  wire [31:0] sb_st_wdata = (m1_mem_width == `MEM_WORD) ? m1_rs2 :
                            (m1_mem_width == `MEM_HALF) ? {2{m1_rs2[15:0]}} :
                                                          {4{m1_rs2[7:0]}};
  wire [3:0]  sb_ld_need  = (e2_mem_width == `MEM_WORD) ? 4'b1111 :
                            (e2_mem_width == `MEM_HALF) ? (e2_alu_out[1] ? 4'b1100 : 4'b0011) :
                                                          (4'b0001 << e2_alu_out[1:0]);
  wire [3:0]  d1_ld_need  = (e1_mem_width == `MEM_WORD) ? 4'b1111 :
                            (e1_mem_width == `MEM_HALF) ? (spec_ld_lane[1] ? 4'b1100 : 4'b0011) :
                                                          (4'b0001 << spec_ld_lane);
`endif
  store_buffer #(.N(4)) u_sb (
      .clk     (clk),
      .rst     (rst),
      .st_en   (m1_mem_we && dram_range),
`ifdef SUBWORD_FAST
      .st_mask (sb_st_mask),
      .st_waddr(m1_alu_out[17:2]),
      .st_wdata(sb_st_wdata),
`ifdef SUBWORD_SPEC
      .ld_en   (e2_mem_re && e2_sb_range),
`else
      // d1-only:EX2口只查word —— 子字命中数据不经格式化,不能混进转发腿
      .ld_en   (e2_mem_re && (e2_mem_width == `MEM_WORD) && e2_sb_range),
`endif
      .ld_need (sb_ld_need),
`else
      .st_word (m1_mem_width == `MEM_WORD),
      .st_waddr(m1_alu_out[17:2]),
      .st_wdata(m1_rs2),
      .ld_en   (e2_mem_re && (e2_mem_width == `MEM_WORD) && e2_sb_range),
`endif
      .ld_raddr(e2_alu_out[17:2]),
      .ld_hit  (sb_ld_hit),
      .ld_data (sb_ld_data),
      .ld2_raddr(spec_ld_waddr),
`ifdef SUBWORD_FAST
      .ld2_need(d1_ld_need),
`endif
      .ld2_hit (d1_sb_hit),
      .ld2_data(d1_sb_data)
  );

  // ---- L0 数据缓存:访存级顺手填充,执行级提前查询 ----
  // word load 完成时记下读到的数据,word store 提交时写穿一份,子字 store 作废对应项;
  // 填充数据与写回数据取自同一处,天然与数据存储器一致。只在流水线推进的拍写入。
  wire        l0_hit;
  wire [31:0] l0_data;
  wire        m1_word   = (m1_mem_width == `MEM_WORD);
  // L0填充放在WB拍,数据地址全取寄存器(直连存储器输出的线太长,时序不收敛)
  // 写存储器(MEM1)与填L0(WB)差一拍:这拍读同地址会命中优先级更高的store_buffer,不会拿旧值
  reg        w_mem_we_r, w_mem_re_r, w_word_r, w_drange_r;
  reg [31:0] w_rs2_r;
  always @(posedge clk) begin
    if (rst) begin w_mem_we_r <= 1'b0; w_mem_re_r <= 1'b0; w_word_r <= 1'b0; w_drange_r <= 1'b0; end
    else if (!stall_back) begin
      w_mem_we_r <= m1_mem_we;  w_mem_re_r <= m1_mem_re;
      w_word_r   <= m1_word;    w_drange_r <= dram_range;  w_rs2_r <= m1_rs2;
    end
  end
  wire        l0_fill   = w_drange_r && w_word_r && (w_mem_re_r || w_mem_we_r);
  wire        l0_invald = w_drange_r && !w_word_r && w_mem_we_r;
  wire [31:0] l0_wdata  = w_mem_we_r ? w_rs2_r : w_mem_rdata;   // 全为寄存器源
  l0_cache u_l0 (
      .clk(clk), .rst(rst),
      .ld_raddr(spec_ld_waddr), .ld_hit(l0_hit), .ld_data(l0_data),
      .wr_en(l0_fill), .wr_inv(l0_invald),
      .wr_addr(w_alu_out[17:2]), .wr_data(l0_wdata)
  );

  // ---- 提前一级查表:用ID预测的地址在EX1就查store_buffer/L0 ----
  // 拿不准的按未命中算(同拍store在写/EX2还有更老的store),回落到EX2查表或存储器读
  wire d1_hit = spec_addr_valid && (d1_sb_hit || l0_hit)
                 && !(m1_mem_we && dram_range && (m1_alu_out[17:2] == spec_ld_waddr))
                 && !(e2_mem_we && (e2_alu_out[17:2] == spec_ld_waddr));

  // 命中的数据存一拍:下一拍消费者到EX1,从选择器的EX2P那一路取用
  always @(posedge clk) begin
`ifdef SUBWORD_FAST
    // 子字load在此完成车道提取+扩展(缓冲/L0条目都是整字);
    // 车道用译码级预测的spec_ld_lane,和真实地址的一致性由A1b断言逐次对账。
    if (d1_hit && !stall_back) d1_data_reg <= ld_fmt(d1_sb_hit ? d1_sb_data : l0_data,
                                                     e1_mem_width, e1_mem_sign, spec_ld_lane);
`else
    if (d1_hit && !stall_back) d1_data_reg <= d1_sb_hit ? d1_sb_data : l0_data;
`endif
  end

`ifdef SUBWORD_FAST
  // d1命中旗标随载荷推进到EX2:距离2的消费者在ID级凭它放行(e2_ld_ready),
  // 下拍从MEM1腿取接力进mem1_fwd_reg的d1_data_reg。冲刷语义与e2_spec_rd同。
  always @(posedge clk) begin
    if (rst) e2_d1_ld <= 1'b0;
    else if (!stall_back) begin
      if (predict_wrong | trap_redirect | mdu_stall) e2_d1_ld <= 1'b0;
      else e2_d1_ld <= d1_hit;
    end
  end
`endif

  assign e2_sb_hit = sb_ld_hit;

  // store→load同地址直传:sw X; lw X 紧挨着时(store在MEM1、load在EX2),store的写数据
  // 就是load该拿的值 —— 直接当预选寄存器的一路传下去,该load连存储器都不用再读。
  assign e2_st2ld_fwd = st_conflict && e2_mem_re && e2_sb_range && dram_range &&
                    (e2_mem_width == `MEM_WORD) && (m1_mem_width == `MEM_WORD);
  wire e2_fast_hit = e2_sb_hit || e2_st2ld_fwd;
`ifdef SUBWORD_FAST
  // EX2载荷"下拍MEM1腿可转发"总闸:缓冲命中/直传/投机读/d1接力,四路任一
  wire e2_ld_ready = e2_fast_hit || e2_spec_rd_hit || e2_d1_ld;
`else
  wire e2_ld_ready = e2_fast_hit || e2_spec_rd_hit;
`endif

  always @(posedge clk) begin
    if (rst) m1_st2ld_fwd <= 1'b0;
    else if (!stall_back) m1_st2ld_fwd <= e2_st2ld_fwd;
  end

  // load结果:按访存宽度截取字节/半字并做符号扩展,整字原样用
  assign m1_mem_rdata =
        m1_mem_re ? (
          (m1_mem_width == `MEM_BYTE) ? (m1_mem_sign ? {{24{perip_rdata[7]}}, perip_rdata[7:0]} : {24'd0, perip_rdata[7:0]}) :
          (m1_mem_width == `MEM_HALF) ? (m1_mem_sign ? {{16{perip_rdata[15]}}, perip_rdata[15:0]} : {16'd0, perip_rdata[15:0]}) :
          perip_rdata
      ) : 32'h0;

  mem_wb_reg u_mem_wb_reg (
      .clk(clk),
      .rst(rst),
      .stall(stall_back),
      .pc4_in(m1_pc4),
      .instr_in(m1_instr),
      .alu_out_in(m1_is_pmul ? pmul_out : m1_alu_out),   // 乘法结果在这里并进写回通路
      .mem_rdata_in((m1_spec_rd || m1_st2ld_fwd) ? mem1_fwd_reg : m1_mem_rdata), // 投机读/直传的 load 写回值取已捕获的寄存器
      .rd_addr_in(m1_rd_addr),
      .reg_we_in(m1_reg_we),
      .wb_sel_in(m1_wb_sel),
      .fused_in(m1_fused),
      .valid_in(m1_valid),
      .w_pc4(w_pc4),
      .w_instr(w_instr),
      .w_alu_out(w_alu_out),
      .w_mem_rdata(w_mem_rdata),
      .w_rd_addr(w_rd_addr),
      .w_reg_we(w_reg_we),
      .w_wb_sel(w_wb_sel),
      .w_fused(w_fused),
      .w_valid(w_valid)
  );

  // -------------------- WB(写回)--------------------
  // 访存第 2 拍与写回合并成一级:load 数据到达的那一拍直接写回寄存器堆,省一排流水寄存器。
  assign wb_data = (w_wb_sel == `WB_ALU) ? w_alu_out : (w_wb_sel == `WB_MEM) ? w_mem_rdata : w_pc4;

  // -------------------- 冲突检测与转发 --------------------
  // 转发选择在ID提前算好、打一拍给EX1用(EX1现场比较地址的路径太长)。
  // 注意错位:按"下一拍各自的位置"比 —— 现在EX1的按EX2算,现在EX2的按MEM1算,依此类推
  wire d_rs1_en = (d_instr[6:0] != 7'b011_0111) && (d_instr[6:0] != 7'b001_0111) && (d_instr[6:0] != 7'b110_1111);   // lui/auipc/jal不读rs1
  wire d_rs2_en = !alu_src_d || mem_we_d || branch_d;   // 只有R型运算/store/分支真的用rs2

  forward_unit u_forward_pre (
      .e1_rs1_addr(rs1_addr),         // ID 后续指令 rs1 = d_instr[19:15]
      .e1_rs2_addr(rs2_addr),         // ID 后续指令 rs2 = d_instr[24:20]
      .e1_rs1_en(d_rs1_en),
      .e1_rs2_en(d_rs2_en),
      .e2_rd_addr(e1_rd_addr),  .e2_reg_we(e1_reg_we),  .e2_wb_sel(e1_wb_sel),   // e2口接现在EX1的:下一拍它在EX2
      .e2_is_pmul(e1_is_mul),                                                    // EX1 的乘法下拍在 EX2 结果还没好
      .e2_load_ok(d1_hit),                                                    // EX1 查缓冲命中的 load,下拍在 EX2 即可转发
      .m1_rd_addr(e2_rd_addr),  .m1_reg_we(e2_reg_we),  .m1_wb_sel(e2_wb_sel),   // m1口接现在EX2的:下一拍它在MEM1
      .m1_load_ok(e2_ld_ready),                                     // 缓冲命中/直传/提前读/d1接力的 load,下拍在 MEM1 即可转发
      .m1_is_pmul(e2_is_pmul),                    // EX2的乘法下一拍结果还没好,不能转发
      .w_rd_addr(m1_rd_addr),  .w_reg_we(m1_reg_we),  .w_wb_sel(m1_wb_sel),   // w口接现在MEM1的:下一拍它在WB,load数据也已就绪
      .fwd_a(fwd_a_pre),
      .fwd_b(fwd_b_pre)
  );

  hazard_unit u_hazard (
      .rs1_id(rs1_addr),
      .rs2_id(rs2_addr),
      .rs1_en(rs1_en_d),
      .rs2_en(rs2_en_d),
      .e1_rd_addr(e1_rd_addr),
      .e1_mem_re(e1_mem_re),
      .e1_is_mul(e1_is_mul),
      .d1_hit(d1_hit),
      .e2_rd_addr(e2_rd_addr),
      .e2_mem_re(e2_mem_re),
      .e2_ld_ok(e2_ld_ready),
      .e2_is_pmul(e2_is_pmul),
      .m1_rd_addr(m1_rd_addr),
      .m1_mem_re(m1_mem_re),
      .dram_stall(dram_stall),
      .stall(load_use_stall)
  );

  // -------------------- 全局停顿与冲刷 --------------------
  // 预测错的三种情况。注意这几个信号在关键路径上:predict_wrong当拍就要冲刷三级流水并改PC
  wire predict_dir_wrong = e2_branch && (e2_branch_taken != e2_predict_taken);
  wire predict_target_bad = e2_branch && e2_branch_taken && (e2_pc_target != e2_predict_target);
  wire predict_jump_bad = e2_jump && (e2_pc_target != e2_predict_target);
  // 预测错在EX2当拍处理:冲掉IF/ID、ID/EX1、EX1/EX2三级错路指令,PC改到正确地址
  // 触发:方向猜错/jalr未预测/目标不对(RAS未中);另两道保险(非跳转被预测跳/分支目标不符)
  // 保证预测表全错也只是慢,不会算错
  wire predict_spurious = e2_predict_taken && !e2_branch && !e2_jump;
  assign predict_wrong = (predict_dir_wrong || (e2_jump && !e2_predict_taken) || predict_jump_bad
                          || predict_target_bad || predict_spurious)
                         && !stall_back;

  // CSR的写是延后一拍才真正生效的,所以紧跟在CSR写后面的CSR/mret/ecall要停一两拍,
  // 等前面那个写完再走,保证读到的是新值
  wire csr_raw_stall = (is_csr_d || is_mret_d || is_ecall_d) && (e1_is_csr || csrw_we_r);

  // 除法多周期期间也要停 PC/IF/ID/EX1 上的所有指令
  assign stall = load_use_stall || dram_stall || mdu_stall || csr_raw_stall;
  // trap 时也要冲刷 IF/ID 和 ID/EX1，与分支预测错误同理
  assign flush_if_id = predict_wrong | trap_redirect;
  // 除法还在算（mdu_is_op && !mdu_finished）时不能因 load_use_stall 冲刷 id_ex1_reg，
  // 否则会把多周期指令弄丢；mdu_finished 那拍允许冲刷，让除法结果顺利前推到 EX2
  wire ex1_can_advance = !dram_stall && (!mdu_is_op || mdu_finished);
  assign flush_id_ex1 = ((load_use_stall || csr_raw_stall) && ex1_can_advance) || predict_wrong | trap_redirect;


  // stall_back 的上一拍值:mem_wb_reg 只在 stall_back=0 的拍锁入新数据,
  // 故「上一拍 stall_back=0 且本拍 w_valid」即代表写回级真的收到了一条新指令。
  always @(posedge clk) begin
    if (rst) stall_back_prev <= 1'b0;
    else     stall_back_prev <= stall_back;
  end

endmodule
