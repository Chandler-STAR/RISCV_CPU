`include "../include/defines.vh"

module myCPU (
    input wire cpu_rst,
    input wire cpu_clk,

    // Interface to IROM
    output wire [31:0] irom_addr,
    input  wire [31:0] irom_data,

    // Interface to DRAM & Peripherals
    output wire [31:0] perip_addr,
    output wire        perip_wen,
    output wire [ 1:0] perip_mask,
    output wire [31:0] perip_wdata,
    input  wire [31:0] perip_rdata
);

  wire clk = cpu_clk;
  wire rst = cpu_rst;

  //========================================== 导线定义 =================================
  wire flush_if_id;
  wire flush_id_ex;
  wire stall;

  // 前递控制
  wire [1:0] fwd_a, fwd_b;

  // IF模块
  wire [31:0] pc, pc4, pc_next;
  wire pc_sel;

  // IF/ID 寄存器输出
  wire [31:0] d_pc, d_pc4, d_instr;
  wire d_predict_taken;
  wire [31:0] d_predict_target;

  // ID模块输出
  wire [4:0] rs1_addr, rs2_addr, rd_addr_d;
  wire [2:0] funct3_d;
  wire [31:0] rs1_rf, rs2_rf, imm;

  // Ctrl模块输出
  wire reg_we_d, mem_we_d, mem_re_d, branch_d, jump_d, alu_src_d, mem_sign_d;
  wire [1:0] wb_sel_d, mem_width_d;
  wire [3:0] alu_op_d;

  // ID/EX 寄存器输出
  wire [31:0] e_pc, e_pc4, e_instr, e_rs1, e_rs2, e_imm;
  wire [4:0] e_rd_addr;
  wire e_reg_we, e_mem_we, e_mem_re, e_branch, e_jump, e_alu_src, e_mem_sign;
  wire [1:0] e_wb_sel, e_mem_width;
  wire [3:0] e_alu_op;

  // EX模块
  wire [31:0] alu_a_final, alu_a_fwd, alu_b_rs2, alu_b, alu_out;
  wire        zero;
  wire        branch_taken_ex;  // 【修改】由 EX 阶段的 branch_comp 产生
  wire [31:0] pc_branch;

  // EX/MEM 寄存器输出
  wire [31:0] m_pc4, m_instr, m_alu_out, m_rs2;
  wire [4:0] m_rd_addr;
  wire m_reg_we, m_mem_we, m_mem_re, m_mem_sign;
  wire [1:0] m_wb_sel, m_mem_width;

  // MEM/WB 寄存器输出
  wire [31:0] w_pc4, w_instr, w_alu_out, w_mem_rdata;
  wire [ 4:0] w_rd_addr;
  wire        w_reg_we;
  wire [ 1:0] w_wb_sel;

  wire [31:0] wd;

  //分支预测
  wire        predict_taken;
  wire [31:0] predict_target;
  wire        predict_direction_wrong;
  wire        predict_target_wrong;
  wire        predict_wrong;
  wire        e_predict_taken;
  wire [31:0] e_predict_target;

  // ====================== 外部总线连接 ======================
  assign irom_addr = pc;
  wire [31:0] instr_if = irom_data;

  assign perip_addr  = m_alu_out;
  assign perip_wen   = m_mem_we;
  assign perip_mask  = m_mem_width;
  assign perip_wdata = m_rs2;

  wire [31:0] mem_rdata;
  assign mem_rdata = m_mem_re ? (
        (m_mem_width == `MEM_BYTE) ? (m_mem_sign ? {{24{perip_rdata[7]}}, perip_rdata[7:0]} : perip_rdata) :
        (m_mem_width == `MEM_HALF) ? (m_mem_sign ? {{16{perip_rdata[15]}}, perip_rdata[15:0]} : perip_rdata) :
        perip_rdata
    ) : 32'h0;

  // ====================== 字段提取 ======================
  assign rs1_addr = d_instr[19:15];
  assign rs2_addr = d_instr[24:20];
  assign rd_addr_d = d_instr[11:7];
  assign funct3_d = d_instr[14:12];

  // ====================== EX阶段组合逻辑 ======================

  // 1. ALU 前递选择 (EX阶段已有的逻辑)
  assign alu_a_fwd = (fwd_a == `FWD_M) ? m_alu_out : (fwd_a == `FWD_W) ? wd : e_rs1;
  assign alu_b_rs2 = (fwd_b == `FWD_M) ? m_alu_out : (fwd_b == `FWD_W) ? wd : e_rs2;

  // 2. ALU 操作数选择
  wire use_pc = (e_alu_op == `ALU_AUIPC) || e_branch || (e_instr[6:0] == 7'b110_1111);
  assign alu_a_final = use_pc ? e_pc : alu_a_fwd;
  assign alu_b = e_alu_src ? e_imm : alu_b_rs2;

  // 3. 【修改】BranchComp 模块移至此处 (使用 EX 阶段的前递值)
  branch_comp u_branch_comp (
      .rs1_bc                 (alu_a_fwd),               // 使用 EX 段前递后的 rs1 值
      .rs2_bc                 (alu_b_rs2),               // 使用 EX 段前递后的 rs2 值
      .funct3_d               (e_instr[14:12]),          // 使用 EX 段的指令字段
      .e_branch               (e_branch),                // EX 阶段的 branch 信号
      .branch_taken           (branch_taken_ex),         // 输出 EX 阶段的比较结果
      .predict_taken_in       (e_predict_taken),         // 来自分支预测器的预测结果
      .predict_direction_wrong(predict_direction_wrong)  // 预测是否正确的信号
  );

  // 4. 跳转与分支逻辑 (在 EX 段计算 pc_sel)


  assign pc_branch = (e_instr[6:0] == 7'b110_0111) ? {alu_out[31:1], 1'b0} : alu_out;
  assign pc_sel = (e_branch & branch_taken_ex) | e_jump;
  assign pc_next = predict_wrong ? (pc_sel ? pc_branch : e_pc4) : (predict_taken ? predict_target : pc4);

  assign predict_target_wrong = e_branch && (e_predict_target != pc_branch);
  assign predict_wrong = predict_direction_wrong || predict_target_wrong||e_jump;// 只要预测方向错误或目标地址错误，就认为预测失败

  // ====================== WB 阶段逻辑 ======================
  assign wd = (w_wb_sel == `WB_ALU) ? w_alu_out : (w_wb_sel == `WB_MEM) ? w_mem_rdata : w_pc4;

  // ====================== 模块例化 ======================
  pc_reg u_pc_reg (
      .clk(clk),
      .rst(rst),
      .stall(stall),
      .pc_next(pc_next),
      .pc(pc),
      .pc4(pc4)
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
      .d_pc4(d_pc4),
      .predict_taken_in(predict_taken),
      .predict_target_in(predict_target),
      .d_predict_taken(d_predict_taken),
      .d_predict_target(d_predict_target)
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
      .clk              (clk),
      .rst              (rst),
      .flush_id_ex      (flush_id_ex),
      .pc_in            (d_pc),
      .pc4_in           (d_pc4),
      .instr_in         (d_instr),
      .rs1_in           (rs1_rf),
      .rs2_in           (rs2_rf),
      .imm_in           (imm),
      .rd_addr_in       (rd_addr_d),
      .reg_we_in        (reg_we_d),
      .mem_we_in        (mem_we_d),
      .mem_re_in        (mem_re_d),
      .branch_in        (branch_d),
      .jump_in          (jump_d),
      .alu_src_in       (alu_src_d),
      .mem_sign_in      (mem_sign_d),
      .wb_sel_in        (wb_sel_d),
      .mem_width_in     (mem_width_d),
      .alu_op_in        (alu_op_d),
      .e_pc             (e_pc),
      .e_pc4            (e_pc4),
      .e_instr          (e_instr),
      .e_rs1            (e_rs1),
      .e_rs2            (e_rs2),
      .e_imm            (e_imm),
      .e_rd_addr        (e_rd_addr),
      .e_reg_we         (e_reg_we),
      .e_mem_we         (e_mem_we),
      .e_mem_re         (e_mem_re),
      .e_branch         (e_branch),
      .e_jump           (e_jump),
      .e_alu_src        (e_alu_src),
      .e_mem_sign       (e_mem_sign),
      .e_wb_sel         (e_wb_sel),
      .e_mem_width      (e_mem_width),
      .e_alu_op         (e_alu_op),
      .e_predict_taken  (e_predict_taken),   // 传递预测结果到 EX 段
      .e_predict_target (e_predict_target),  // 传递预测目标到 EX 段
      .predict_taken_in (d_predict_taken),
      .predict_target_in(d_predict_target)

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
      .fwd_a(fwd_a),
      .fwd_b(fwd_b)  // 删除了分支前递信号
  );

  hazard_unit u_hazard (
      .instr_id     (d_instr),
      .instr_ex     (e_instr),
      .mem_re_ex    (e_mem_re),
      .reg_we_ex    (e_reg_we),
      .pc_sel       (pc_sel),         // 来自 EX 阶段的最终跳转决策信号
      .predict_wrong(predict_wrong),  // 传递预测错误信号到 Hazard Unit
      .stall        (stall),
      .flush_if_id  (flush_if_id),
      .flush_id_ex  (flush_id_ex)
  );

  branch_predictor u_branch_predictor (
      .clk             (clk),
      .rst             (rst),
      .if_pc           (pc),
      .predict_taken   (predict_taken),
      .predict_target  (predict_target),
      .ex_is_branch    (e_branch),
      .ex_pc           (e_pc),
      .ex_actual_taken (branch_taken_ex),
      .ex_actual_target(pc_branch)
  );

endmodule
