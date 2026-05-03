//`include "defines.vh"
`include "../include/defines.vh"

module myCPU (
    input wire cpu_rst,
    input wire cpu_clk,

    output wire [31:0] irom_addr,
    input  wire [31:0] irom_data,

    output wire [31:0] perip_addr,
    output wire        perip_wen,
    output wire [ 1:0] perip_mask,
    output wire [31:0] perip_wdata,
    input  wire [31:0] perip_rdata
);

  // ==================== 1. 全局与控制信号声明 ====================
  wire clk = cpu_clk;
  wire rst = cpu_rst;

  wire stall, flush_if_id, flush_id_ex1;
  wire [2:0] fwd_a, fwd_b;
  wire dram_range, dram_stall, stall_back;
  reg [1:0] dram_wait_cnt;

  // 冲突检测与预测信号
  wire predict_taken, predict_wrong;
  wire [31:0] predict_target;
  wire load_use_stall, load_use_flush, hazard_flush_if_id;

  // ==================== 2. 各流水线阶段信号声明 ====================

  // IF 阶段
  wire [31:0] pc, pc4, pc_next;

  // ID 阶段
  wire [31:0] d_pc, d_pc4, d_instr, d_predict_target;
  wire d_predict_taken;
  wire [4:0] rs1_addr, rs2_addr, rd_addr_d;
  wire [31:0] rs1_rf, rs2_rf, imm;
  wire reg_we_d, mem_we_d, mem_re_d, branch_d, jump_d, alu_src_d, mem_sign_d, rs1_en_d, rs2_en_d;
  wire [1:0] wb_sel_d, mem_width_d;
  wire [3:0] alu_op_d;
  wire [1:0] d_instr_type;

  // EX1 阶段
  wire [31:0] e1_pc, e1_pc4, e1_instr, e1_rs1, e1_rs2, e1_imm, e1_predict_target;
  wire [4:0] e1_rd_addr;
  wire e1_reg_we, e1_mem_we, e1_mem_re, e1_branch, e1_jump, e1_alu_src, e1_mem_sign, e1_predict_taken;
  wire [1:0] e1_wb_sel, e1_mem_width, e1_instr_type;
  wire [ 3:0] e1_alu_op;
  wire [31:0] alu_out;
  wire zero, branch_taken;
  wire [31:0] pc_branch;

  // EX2 阶段
  wire [31:0] e2_pc, e2_pc4, e2_instr, e2_rs2, e2_alu_out, e2_pc_branch, e2_predict_target;
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
  wire [31:0] mem_rdata;

  // MEM2 阶段
  wire [31:0] m2_pc4, m2_instr, m2_alu_out, m2_mem_rdata;
  wire [4:0] m2_rd_addr;
  wire       m2_reg_we;
  wire [1:0] m2_wb_sel;

  // WB 阶段
  wire [31:0] w_pc4, w_instr, w_alu_out, w_mem_rdata, wb_data;
  wire [4:0] w_rd_addr;
  wire       w_reg_we;
  wire [1:0] w_wb_sel;

  // ==================== 3. 逻辑实现 ====================

  // -------------------- IF --------------------
  assign irom_addr = pc;
  assign e2_is_branch_or_jump = e2_branch || e2_jump;

  branch_predictor u_branch_predictor (
      .clk(clk),
      .rst(rst),
      .if_pc(pc),
      .predict_taken(predict_taken),
      .predict_target(predict_target),
      .ex_is_branch(e2_is_branch_or_jump),
      .ex_pc(e2_pc),
      .ex_actual_taken(e2_branch_taken),
      .ex_actual_target(e2_pc_target),
      .ex_instr_type(e2_instr_type),
      .stall_back(stall_back)
  );

  pc_reg u_pc_reg (
      .clk(clk),
      .rst(rst),
      .stall(stall),
      .redirect(predict_wrong),
      .pc_next(pc_next),
      .pc(pc),
      .pc4(pc4)
  );

  if_id_reg u_if_id_reg (
      .clk(clk),
      .rst(rst),
      .flush(flush_if_id),
      .stall(stall),
      .pc_in(pc),
      .pc4_in(pc4),
      .instr_in(irom_data),
      .predict_taken_in(predict_taken),
      .predict_target_in(predict_target),
      .d_pc(d_pc),
      .d_pc4(d_pc4),
      .d_instr(d_instr),
      .d_predict_taken(d_predict_taken),
      .d_predict_target(d_predict_target)
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
      .instr_type(d_instr_type)
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
      .imm_in(imm),
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
      .e1_instr_type(e1_instr_type)
  );

  // -------------------- EX1 --------------------
  wire [31:0] e2_fwd = (e2_wb_sel == `WB_PC4) ? e2_pc4 : e2_alu_out;
  wire [31:0] m1_fwd = (m1_wb_sel == `WB_PC4) ? m1_pc4 : m1_alu_out;


  wire [31:0] alu_a_fwd = (fwd_a == `FWD_EX2)  ? e2_fwd :
                       (fwd_a == `FWD_MEM1) ? m1_fwd :
                       (fwd_a == `FWD_MEM2) ? ((m2_wb_sel == `WB_MEM) ? m2_mem_rdata :
                                               (m2_wb_sel == `WB_PC4) ? m2_pc4 : m2_alu_out) :
                       (fwd_a == `FWD_WB)   ? wb_data : e1_rs1;

  wire [31:0] alu_b_fwd = (fwd_b == `FWD_EX2)  ? e2_fwd :
                       (fwd_b == `FWD_MEM1) ? m1_fwd :
                       (fwd_b == `FWD_MEM2) ? ((m2_wb_sel == `WB_MEM) ? m2_mem_rdata :
                                               (m2_wb_sel == `WB_PC4) ? m2_pc4 : m2_alu_out) :
                       (fwd_b == `FWD_WB)   ? wb_data : e1_rs2;

  wire use_pc = (e1_alu_op == `ALU_AUIPC) || e1_branch || (e1_instr[6:0] == 7'b110_1111);
  wire [31:0] alu_a = use_pc ? e1_pc : alu_a_fwd;
  wire [31:0] alu_b = e1_alu_src ? e1_imm : alu_b_fwd;

  alu u_alu (
      .alu_a(alu_a),
      .alu_b(alu_b),
      .alu_op(e1_alu_op),
      .alu_out(alu_out),
      .zero(zero)
  );

  branch_comp u_branch_comp (
      .rs1_bc(alu_a_fwd),
      .rs2_bc(alu_b_fwd),
      .funct3_d(e1_instr[14:12]),
      .is_branch(e1_branch),
      .branch_taken(branch_taken)
  );

  assign pc_branch = alu_out;

  ex1_ex2_reg u_ex1_ex2_reg (
      .clk(clk),
      .rst(rst),
      .flush(predict_wrong),
      .stall(stall_back),
      .pc_in(e1_pc),
      .pc4_in(e1_pc4),
      .instr_in(e1_instr),
      .rs2_in(alu_b_fwd),
      .alu_out_in(alu_out),
      .pc_branch_in(pc_branch),
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
      .e2_pc(e2_pc),
      .e2_pc4(e2_pc4),
      .e2_instr(e2_instr),
      .e2_rs2(e2_rs2),
      .e2_alu_out(e2_alu_out),
      .e2_pc_branch(e2_pc_branch),
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
      .e2_instr_type(e2_instr_type)
  );

  // -------------------- EX2 --------------------
  assign e2_pc_sel = ((e2_branch & e2_branch_taken) | e2_jump) & ~stall_back;
  assign e2_pc_target = (e2_instr[6:0] == 7'b110_0111) ? {e2_pc_branch[31:1], 1'b0} : e2_pc_branch;
  assign pc_next = predict_wrong ? (e2_pc_sel ? e2_pc_target : e2_pc4) :
                     predict_taken ? predict_target : pc4;

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
      .m1_mem_width(m1_mem_width)
  );

  // -------------------- MEM1 --------------------
  assign perip_addr  = m1_alu_out;
  assign perip_wen   = m1_mem_we;
  assign perip_mask  = m1_mem_width;
  assign perip_wdata = m1_rs2;

  assign dram_range  = (m1_alu_out >= 32'h8010_0000) && (m1_alu_out <= 32'h8013_FFFF);
  assign dram_stall  = m1_mem_re && dram_range && (dram_wait_cnt < 2'd2);
  assign stall_back  = dram_stall;

  always @(posedge clk) begin
    if (rst) dram_wait_cnt <= 2'd0;
    else if (m1_mem_re && dram_range && dram_wait_cnt < 2'd2) dram_wait_cnt <= dram_wait_cnt + 2'd1;
    else if (!stall_back) dram_wait_cnt <= 2'd0;
  end

  assign mem_rdata = m1_mem_re ? (
        (m1_mem_width == `MEM_BYTE) ? (m1_mem_sign ? {{24{perip_rdata[7]}}, perip_rdata[7:0]} : {24'd0, perip_rdata[7:0]}) :
        (m1_mem_width == `MEM_HALF) ? (m1_mem_sign ? {{16{perip_rdata[15]}}, perip_rdata[15:0]} : {16'd0, perip_rdata[15:0]}) :
        perip_rdata
    ) : 32'h0;

  mem1_mem2_reg u_mem1_mem2_reg (
      .clk(clk),
      .rst(rst),
      .stall(stall_back),
      .pc4_in(m1_pc4),
      .instr_in(m1_instr),
      .alu_out_in(m1_alu_out),
      .mem_rdata_in(mem_rdata),
      .rd_addr_in(m1_rd_addr),
      .reg_we_in(m1_reg_we),
      .wb_sel_in(m1_wb_sel),
      .m2_pc4(m2_pc4),
      .m2_instr(m2_instr),
      .m2_alu_out(m2_alu_out),
      .m2_mem_rdata(m2_mem_rdata),
      .m2_rd_addr(m2_rd_addr),
      .m2_reg_we(m2_reg_we),
      .m2_wb_sel(m2_wb_sel)
  );

  // -------------------- MEM2/WB --------------------
  mem2_wb_reg u_mem2_wb_reg (
      .clk(clk),
      .rst(rst),
      .stall(stall_back),
      .pc4_in(m2_pc4),
      .instr_in(m2_instr),
      .alu_out_in(m2_alu_out),
      .mem_rdata_in(m2_mem_rdata),
      .rd_addr_in(m2_rd_addr),
      .reg_we_in(m2_reg_we),
      .wb_sel_in(m2_wb_sel),
      .w_pc4(w_pc4),
      .w_instr(w_instr),
      .w_alu_out(w_alu_out),
      .w_mem_rdata(w_mem_rdata),
      .w_rd_addr(w_rd_addr),
      .w_reg_we(w_reg_we),
      .w_wb_sel(w_wb_sel)
  );

  assign wb_data = (w_wb_sel == `WB_ALU) ? w_alu_out : (w_wb_sel == `WB_MEM) ? w_mem_rdata : w_pc4;

  // -------------------- 辅助单元与冲突控制 --------------------
  wire e1_rs1_en = (e1_instr[6:0] != 7'b011_0111) &&  (e1_instr[6:0] != 7'b001_0111) &&  (e1_instr[6:0] != 7'b110_1111);
  wire e1_rs2_en = !e1_alu_src || e1_mem_we || e1_branch;

  forward_unit u_forward (
      .e1_rs1_addr(e1_instr[19:15]),
      .e1_rs2_addr(e1_instr[24:20]),
      .e1_rs1_en(e1_rs1_en),
      .e1_rs2_en(e1_rs2_en),
      .e2_rd_addr(e2_rd_addr),
      .e2_reg_we(e2_reg_we),
      .e2_wb_sel(e2_wb_sel),
      .m1_rd_addr(m1_rd_addr),
      .m1_reg_we(m1_reg_we),
      .m1_wb_sel(m1_wb_sel),
      .m2_rd_addr(m2_rd_addr),
      .m2_reg_we(m2_reg_we),
      .m2_wb_sel(m2_wb_sel),
      .w_rd_addr(w_rd_addr),
      .w_reg_we(w_reg_we),
      .fwd_a(fwd_a),
      .fwd_b(fwd_b)
  );

  hazard_unit u_hazard (
      .rs1_id(rs1_addr),
      .rs2_id(rs2_addr),
      .rs1_en(rs1_en_d),
      .rs2_en(rs2_en_d),
      .e1_rd_addr(e1_rd_addr),
      .e1_mem_re(e1_mem_re),
      .e2_rd_addr(e2_rd_addr),
      .e2_mem_re(e2_mem_re),
      .m1_rd_addr(m1_rd_addr),
      .m1_mem_re(m1_mem_re),
      .dram_stall(dram_stall),
      .e2_pc_sel(e2_pc_sel),
      .stall(load_use_stall),
      .flush_if_id(hazard_flush_if_id),
      .flush_id_ex1(load_use_flush)
  );

  wire predict_dir_wrong = e2_branch && (e2_branch_taken != e2_predict_taken);
  wire predict_target_bad = e2_branch && e2_branch_taken && (e2_pc_target != e2_predict_target);
  wire predict_jump_bad = e2_jump && (e2_pc_target != e2_predict_target);
  assign predict_wrong = (predict_dir_wrong || predict_target_bad || predict_jump_bad) && !stall_back;

  assign stall = load_use_stall || dram_stall;
  assign flush_if_id = predict_wrong;
  assign flush_id_ex1 = (load_use_stall && !dram_stall) || predict_wrong;

endmodule
