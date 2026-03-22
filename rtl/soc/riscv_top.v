`include "defines.vh"

module riscv_top (
    input wire clk,
    input wire rst
);
    
endmodule
//──────────────────────────────────导线定义─────────────────────────────
//       先定义一堆导线
//       没有前缀的：pc_reg输出以及imem的输出
//       d_前缀：if_id_reg   模块输出
//       e_前缀：id_ex_reg   模块输出
//       m_前缀：ex_mem_reg  模块输出
//       w_前缀：mem_wb_reg  模块输出
//  名称与模块输出一样，比如pc_reg模块输出pc和pc4，
//  那么定义wire pc和pc4，imem模块输出instr_if，那么定义wire instr_if,用于连接前后级
//  模块例化，先写输入再写输出
//─────────────────────────────────────────


//冒险信号
wire flush;
wire stall;

// 前递控制
wire [1:0]  fwd_a, fwd_b;
wire        fwd_br_a, fwd_br_b;

//if模块 pc_reg、imem、pc_mux
wire [31:0] pc;         //pc_reg输出    
wire [31:0] pc4;        //pc_reg输出
wire [31:0] pc_next;    //pc_mux输出
wire        pc_sel;     //分支/跳转触发,pc_mux选择信号
wire [31:0] instr_if;    //imem输出



//if_id_reg模块
wire [31:0] d_pc;       //id_ex_reg输出
wire [31:0] d_pc4;      //id_ex_reg输出
wire [31:0] d_instr;    //id_ex_reg输出



//id模块 imm_gen、regfile、ctrl、branch_comp            
wire [4:0]  rs1_addr;                //regfile读地址1输入
wire [4:0]  rs2_addr;                    //regfile读地址2输入
wire [4:0]  rd_addr_d;               //regfile写地址输入
wire [2:0]  funct3_d;                //指令funct3字段
wire [31:0] rs1_rf;                      //regfile 输出
wire [31:0] rs2_rf;                  // regfile 输出
wire [31:0] rs1_bc;              // BranchComp 前递输入,
wire [31:0] rs2_bc;              // BranchComp 前递后输入
wire [31:0] imm;                             // imm_gen 输出
wire        branch_taken;                   // branch_comp 输出  
//ctrl模块输出
wire        reg_we_d;
wire        mem_we_d;
wire        mem_re_d;
wire        branch_d;
wire        jump_d;
wire        alu_src_d;
wire        mem_sign_d;
wire [1:0]  wb_sel_d;
wire [1:0]  mem_width_d;
wire [3:0]  alu_op_d;

//id_ex_reg模块输出
wire [31:0] e_pc, 
wire [31:0] e_pc4, 
wire [31:0] e_instr;
wire [31:0] e_rs1, 
wire [31:0] e_rs2,
wire [31:0] e_imm;
wire [4:0]  e_rd_addr;
wire        e_branch_taken;
wire        e_reg_we;
wire        e_mem_we;
wire        e_mem_re;
wire        e_branch;
wire        e_jump;
wire        e_alu_src;
wire        e_mem_sign;
wire [1:0]  e_wb_sel;
wire [1:0]  e_mem_width;
wire [3:0]  e_alu_op;

//ex模块 alu、 前递MUX A、前递MUX B
wire [31:0] alu_a_final;   // 前递 MUX A 后（含 pc 替换）
wire [31:0] alu_a_fwd;     // 纯前递 MUX A 输出（rs1 方向）
wire [31:0] alu_b_rs2;     // 前递 MUX B 输出（rs2 方向，未过 alu_src）
wire [31:0] alu_b;         // alu_src MUX 最终输出
wire [31:0] alu_out;       // ALU 结果，兼分支目标地址
wire        zero;
wire [31:0] pc_branch;     // 实际跳转目标（JALR 清 bit0）

//──────────────────────────────────导线定义─────────────────────────────





//顶层组合逻辑
//─────────────────────字段提取─────────────────────
assign rs1_addr  = d_instr[19:15];
assign rs2_addr  = d_instr[24:20];
assign rd_addr_d = d_instr[11:7];
assign funct3_d  = d_instr[14:12];
//─────────────────────────────────────────────────

//──────────────BranchComp 前递 MUX ────────────
assign rs1_bc = fwd_br_a ? m_alu_out : rs1_rf;
assign rs2_bc = fwd_br_b ? m_alu_out : rs2_rf;
//─────────────────────────────────────────────────



//模块例化
pc_reg u_pc_reg(
    .clk(clk),
    .rst(rst),
    .stall(stall),
    .pc_next(pc_next),    
    .pc(pc),
    .pc4(pc4)
);

imem u_imem(
    .pc(pc),
    .instr_if(instr_if)
);

if_id_reg u_if_id_reg(
    .clk(clk),
    .rst(rst),
    .pc_in(pc),
    .pc4_in(pc4),
    .instr_in(instr_if),
    .d_instr(d_instr)，
    .stall(stall),
    .flush(flush),
    .d_pc(d_pc),
    .d_pc4(d_pc4)
);

regfile u_regfile(
    .clk(clk),
    .rs1_addr(rs1_addr),
    .rs2_addr(rs2_addr),
    .rd_addr(w_rd_addr),
    .wd(wd),
    .reg_we(w_reg_we),
    .rs1_rf(rs1_rf),
    .rs2_rf(rs2_rf)
);

branch_comp u_branch_comp(
    .rs1_bc(rs1_bc),
    .rs2_bc(rs2_bc),
    .funct3_d(funct3_d),
    .branch_taken(branch_taken)
);

ctrl u_ctrl(
    .d_instr(d_instr),
    .reg_we_d(reg_we_d),   
    .mem_we_d(mem_we_d),
    .mem_re_d(mem_re_d),   
    .branch_d(branch_d),
    .jump_d(jump_d),     
    .alu_src_d(alu_src_d),
    .wb_sel_d(wb_sel_d),   
    .alu_op(alu_op_d),
    .mem_width_d(mem_width_d),
    .mem_sign_d(mem_sign_d)
);

id_ex_reg u_id_ex_reg(
    .clk(clk),
    .rst(rst),
    .flush(flush),
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

alu u_alu(
    .alu_a(alu_a_final),
    .alu_b(alu_b),
    .alu_op(e_alu_op),
    .alu_out(alu_out),
    .zero(zero)
);




