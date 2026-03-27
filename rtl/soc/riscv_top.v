`include "../include/defines.vh"

module riscv_top (
    input wire clk,
    input wire rst
);


  //==========================================导线定义================================
  //       先定义一堆导线
  //       没有前缀的：pc_reg输出以及imem的输出
  //       d_前缀：if_id_reg   模块输出
  //       e_前缀：id_ex_reg   模块输出
  //       m_前缀：ex_mem_reg  模块输出
  //       w_前缀：mem_wb_reg  模块输出
  //  名称与模块输出一样，比如pc_reg模块输出pc和pc4，
  //  那么定义wire pc和pc4，imem模块输出instr_if，那么定义wire instr_if,用于连接前后级
  //  模块例化，先写输入再写输出



  //冒险信号
  wire flush_if_id; // 替换原有的 wire flush;
  wire flush_id_ex;
  wire stall;

  // 前递控制
  wire [1:0] fwd_a, fwd_b;
  wire [1:0] fwd_br_a, fwd_br_b;

  //if模块 pc_reg、imem、pc_mux
  wire [31:0] pc;  //pc_reg输出    
  wire [31:0] pc4;  //pc_reg输出
  wire [31:0] pc_next;  //pc_mux输出
  wire        pc_sel;  //分支/跳转触发,pc_mux选择信号
  wire [31:0] instr_if;  //imem输出



  //if_id_reg模块
  wire [31:0] d_pc;  //id_ex_reg输出
  wire [31:0] d_pc4;  //id_ex_reg输出
  wire [31:0] d_instr;  //id_ex_reg输出



  //id模块 imm_gen、regfile、ctrl、branch_comp            
  wire [ 4:0] rs1_addr;  //regfile读地址1输入
  wire [ 4:0] rs2_addr;  //regfile读地址2输入
  wire [ 4:0] rd_addr_d;  //regfile写地址输入
  wire [ 2:0] funct3_d;  //指令funct3字段
  wire [31:0] rs1_rf;  //regfile 输出
  wire [31:0] rs2_rf;  // regfile 输出
  wire [31:0] rs1_bc;  // BranchComp 前递输入,
  wire [31:0] rs2_bc;  // BranchComp 前递后输入
  wire [31:0] imm;  // imm_gen 输出
  wire        branch_taken;  // branch_comp 输出  
  //ctrl模块输出
  wire        reg_we_d;
  wire        mem_we_d;
  wire        mem_re_d;
  wire        branch_d;
  wire        jump_d;
  wire        alu_src_d;
  wire        mem_sign_d;
  wire [ 1:0] wb_sel_d;
  wire [ 1:0] mem_width_d;
  wire [ 3:0] alu_op_d;

  //id_ex_reg模块输出
  wire [31:0] e_pc;
  wire [31:0] e_pc4;
  wire [31:0] e_instr;
  wire [31:0] e_rs1;
  wire [31:0] e_rs2;
  wire [31:0] e_imm;
  wire [ 4:0] e_rd_addr;
  wire        e_branch_taken;
  wire        e_reg_we;
  wire        e_mem_we;
  wire        e_mem_re;
  wire        e_branch;
  wire        e_jump;
  wire        e_alu_src;
  wire        e_mem_sign;
  wire [ 1:0] e_wb_sel;
  wire [ 1:0] e_mem_width;
  wire [ 3:0] e_alu_op;

  //ex模块 alu、 前递MUX A、前递MUX B
  wire [31:0] alu_a_final;  // 前递 MUX A 后（含 pc 替换）
  wire [31:0] alu_a_fwd;  // 纯前递 MUX A 输出（rs1 方向）
  wire [31:0] alu_b_rs2;  // 前递 MUX B 输出（rs2 方向，未过 alu_src）
  wire [31:0] alu_b;  // alu_src MUX 最终输出
  wire [31:0] alu_out;  // ALU 结果，也是分支目标地址
  wire        zero;  //alu输出是否为0，分支比较结果,辅助调试用
  wire [31:0] pc_branch;  // 实际跳转目标（JALR 清 bit0）

  //ex_mem_reg模块
  wire [31:0] m_pc4;  // 访存阶段pc+4
  wire [31:0] m_instr;  // 访存阶段指令
  wire [31:0] m_alu_out;  // ALU结果
  wire [31:0] m_rs2;  // rs2值
  wire [ 4:0] m_rd_addr;  // 访存阶段目的寄存器地址
  wire        m_reg_we;  // 访存阶段寄存器写使能
  wire        m_mem_we;  // 访存阶段数据写使能
  wire        m_mem_re;  // 访存阶段数据读使能
  wire        m_mem_sign;  // 访存阶段数据符号扩展控制
  wire [ 1:0] m_wb_sel;  // 访存阶段写回选择
  wire [ 1:0] m_mem_width;  // 访存阶段数据宽度

  //mem模块
  wire [31:0] mem_rdata;  //dmem输出

  //mem_wb_reg模块
  wire [31:0] w_pc4;  // 写回阶段pc+4
  wire [31:0] w_instr;  // 写回阶段指令
  wire [31:0] w_alu_out;  // 写回阶段ALU结果
  wire [31:0] w_mem_rdata;  // 写回阶段访存数据
  wire [ 4:0] w_rd_addr;  // 写回阶段目的寄存器地址
  wire        w_reg_we;  // 写回阶段寄存器写使能
  wire [ 1:0] w_wb_sel;  // 写回阶段写回选择

  //wb模块 
  wire [31:0] wd;  // WB MUX 输出，写回 regfile

  //==========================================导线定义================================





  //==========================================顶层组合逻辑================================
  //─────────────────────字段提取─────────────────────────────
  assign rs1_addr  = d_instr[19:15];
  assign rs2_addr  = d_instr[24:20];
  assign rd_addr_d = d_instr[11:7];
  assign funct3_d  = d_instr[14:12];
  //─────────────────────────────────────────────────────────

  //──────────────────────BranchComp 前递 MUX ─────────────────────────────────────────
   assign rs1_bc = (fwd_br_a == 2'b01) ? m_alu_out :  (fwd_br_a == 2'b10) ? wd  : rs1_rf;
   assign rs2_bc = (fwd_br_b == 2'b01) ? m_alu_out :  (fwd_br_b == 2'b10) ? wd  : rs2_rf;
  //────────────────────────────────────────────────────────────────────────────────────


  //──────────────────ALU 前递 MUX A（3选1：寄存器值、访存阶段前递、写回阶段前递）────────────────────
  assign alu_a_fwd = (fwd_a == `FWD_M) ? m_alu_out : (fwd_a == `FWD_W) ? wd : e_rs1;
  //─────────────────────────────────────────────────────────────────────────────────────────


  // ───────────────── ALU前递 MUX B（3选1：寄存器值、访存阶段前递、写回阶段前递）──────────────
  assign alu_b_rs2 = (fwd_b == `FWD_M) ? m_alu_out : (fwd_b == `FWD_W) ? wd : e_rs2;
  //──────────────────────────────────────────────────────────────────────────────────────────


  // ─────────────────────── ALU操作数a MUX(2选1：alu前递值a、pc值（JAL指令）)──────────────────
  wire use_pc = (e_alu_op == `ALU_AUIPC) ||       
              e_branch                 ||
              (e_instr[6:0] == 7'b110_1111); // AUIPC、JAL等需要将alu_a_final设为pc以计算跳转目标地址
  assign alu_a_final = use_pc ? e_pc : alu_a_fwd;
  //──────────────────────────────────────────────────────────────────────────────────────────



  // ─────────────────────────── ALU操作数b MUX(2选1：alu前递值b、立即数)──────────────────────
  assign alu_b = e_alu_src ? e_imm : alu_b_rs2;
  //───────────────────────────────────────────────────────────────────────────────────────



  // ─────────────────────────── PC MUX（JALR 目标地址 bit[0] 必须清零）──────────────────────
  assign pc_branch = (e_instr[6:0] == 7'b110_0111) ?
                   {alu_out[31:1], 1'b0} : alu_out;     //判断是不是JALR，如果是，pc_branch的值为alu_out但最低位强制为0，否则pc_branch就是alu_out（分支目标地址）

  assign pc_sel = (e_branch & e_branch_taken) | e_jump;  //是否需要跳转
  assign pc_next = pc_sel ? pc_branch : pc4;
  //───────────────────────────────────────────────────────────────────────────────────────



  // ─────────────────────────────────────── WB MUX（3选1：ALU结果、访存数据、PC+4） ───────────────────────────────────────
  assign wd = (w_wb_sel == `WB_ALU) ? w_alu_out : (w_wb_sel == `WB_MEM) ? w_mem_rdata : w_pc4;
  //───────────────────────────────────────────────────────────────────────────────────────
  //==========================================顶层组合逻辑================================




  //========================================模块例化================================
  pc_reg u_pc_reg (
      .clk(clk),
      .rst(rst),
      .stall(stall),
      .pc_next(pc_next),
      .pc(pc),
      .pc4(pc4)
  );

  imem u_imem (
      .pc(pc),
      .instr_if(instr_if)
  );

  if_id_reg u_if_id_reg (
      .clk(clk),
      .rst(rst),
      .pc_in(pc),
      .pc4_in(pc4),
      .instr_in(instr_if),
      .d_instr(d_instr),
      .stall(stall),
      .flush_if_id(flush_if_id),
      .d_pc(d_pc),
      .d_pc4(d_pc4)
  );

  imm_gen u_imm_gen (
      .d_instr(d_instr),
      .imm(imm)
  );

  regfile u_regfile (
      .clk(clk),
      .rs1_addr(rs1_addr),
      .rs2_addr(rs2_addr),
      .rd_addr(w_rd_addr),
      .wd(wd),
      .reg_we(w_reg_we),
      .rs1_rf(rs1_rf),
      .rs2_rf(rs2_rf)
  );

  branch_comp u_branch_comp (
      .rs1_bc(rs1_bc),
      .rs2_bc(rs2_bc),
      .funct3_d(funct3_d),
      .branch_taken(branch_taken)
  );

  ctrl u_ctrl (
      .d_instr(d_instr),
      .reg_we_d(reg_we_d),
      .mem_we_d(mem_we_d),
      .mem_re_d(mem_re_d),
      .branch_d(branch_d),
      .jump_d(jump_d),
      .alu_src_d(alu_src_d),
      .wb_sel_d(wb_sel_d),
      .alu_op_d(alu_op_d),
      .mem_width_d(mem_width_d),
      .mem_sign_d(mem_sign_d)
  );

  id_ex_reg u_id_ex_reg (
      .clk(clk),
      .rst(rst),
      .flush_id_ex(flush_id_ex),
      .pc_in(d_pc),
      .pc4_in(d_pc4),
      .instr_in(d_instr),
      .rs1_in(rs1_rf),
      .rs2_in(rs2_rf),
      .imm_in(imm),
      .rd_addr_in(rd_addr_d),
      .branch_taken_in(branch_taken),
      .reg_we_in(reg_we_d),
      .mem_we_in(mem_we_d),
      .mem_re_in(mem_re_d),
      .branch_in(branch_d),
      .jump_in(jump_d),
      .alu_src_in(alu_src_d),
      .mem_sign_in(mem_sign_d),
      .wb_sel_in(wb_sel_d),
      .mem_width_in(mem_width_d),
      .alu_op_in(alu_op_d),
      .e_pc(e_pc),
      .e_pc4(e_pc4),
      .e_instr(e_instr),
      .e_rs1(e_rs1),
      .e_rs2(e_rs2),
      .e_imm(e_imm),
      .e_rd_addr(e_rd_addr),
      .e_branch_taken(e_branch_taken),
      .e_reg_we(e_reg_we),
      .e_mem_we(e_mem_we),
      .e_mem_re(e_mem_re),
      .e_branch(e_branch),
      .e_jump(e_jump),
      .e_alu_src(e_alu_src),
      .e_mem_sign(e_mem_sign),
      .e_wb_sel(e_wb_sel),
      .e_mem_width(e_mem_width),
      .e_alu_op(e_alu_op)
  );

  alu u_alu (
      .alu_a(alu_a_final),
      .alu_b(alu_b),
      .alu_op(e_alu_op),
      .alu_out(alu_out),
      .zero(zero)
  );

  ex_mem_reg u_ex_mem_reg (
      .clk(clk),
      .rst(rst),
      .pc4_in(e_pc4),
      .instr_in(e_instr),
      .alu_out_in(alu_out),
      .rs2_in(alu_b_rs2),
      .rd_addr_in(e_rd_addr),
      .reg_we_in(e_reg_we),
      .mem_we_in(e_mem_we),
      .mem_re_in(e_mem_re),
      .mem_sign_in(e_mem_sign),
      .wb_sel_in(e_wb_sel),
      .mem_width_in(e_mem_width),
      .m_pc4(m_pc4),
      .m_instr(m_instr),
      .m_alu_out(m_alu_out),
      .m_rs2(m_rs2),
      .m_rd_addr(m_rd_addr),
      .m_reg_we(m_reg_we),
      .m_mem_we(m_mem_we),
      .m_mem_re(m_mem_re),
      .m_mem_sign(m_mem_sign),
      .m_wb_sel(m_wb_sel),
      .m_mem_width(m_mem_width)
  );

  dmem u_dmem (
      .clk(clk),
      .alu_out(m_alu_out),
      .rs2(m_rs2),
      .mem_we(m_mem_we),
      .mem_re(m_mem_re),
      .mem_sign(m_mem_sign),
      .mem_width(m_mem_width),
      .mem_rdata(mem_rdata)
  );

  mem_wb_reg u_mem_wb_reg (
      .clk(clk),
      .rst(rst),
      .pc4_in(m_pc4),
      .instr_in(m_instr),
      .alu_out_in(m_alu_out),
      .mem_rdata_in(mem_rdata),
      .rd_addr_in(m_rd_addr),
      .reg_we_in(m_reg_we),
      .wb_sel_in(m_wb_sel),
      .w_pc4(w_pc4),
      .w_instr(w_instr),
      .w_alu_out(w_alu_out),
      .w_mem_rdata(w_mem_rdata),
      .w_rd_addr(w_rd_addr),
      .w_reg_we(w_reg_we),
      .w_wb_sel(w_wb_sel)
  );

  forward_unit u_forward (
      .instr_ex(e_instr),
      .instr_mem(m_instr),
      .reg_we_mem(m_reg_we),
      .mem_re_mem(m_mem_re),
      .instr_wb(w_instr),
      .reg_we_wb(w_reg_we),
      .instr_id(d_instr),
      .fwd_a(fwd_a),
      .fwd_b(fwd_b),
      .fwd_br_a(fwd_br_a),
      .fwd_br_b(fwd_br_b)
  );

  hazard_unit u_hazard (
      .instr_id(d_instr),
      .instr_ex(e_instr),
      .mem_re_ex(e_mem_re),
      .reg_we_ex(e_reg_we),       // 【新增连线】传入 EX 阶段的写使能
      .pc_sel(pc_sel),
      .stall(stall),
      .flush_if_id(flush_if_id),  // 【新增】专门控制 IF/ID 寄存器的清空
      .flush_id_ex(flush_id_ex)   // 【新增】专门控制 ID/EX 寄存器的清空
  );
  //========================================模块例化================================

endmodule  //bug fix 2026-3-22-18-01 endmodule位置错误导致编译器报错
