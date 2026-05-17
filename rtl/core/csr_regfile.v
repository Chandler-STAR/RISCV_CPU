`include "../include/defines.vh"
// CSR 寄存器堆 —— M 模式：mstatus / mepc / mtvec / mcause

module csr_regfile (
    input  wire        clk,
    input  wire        rst,

    // —— 来自 ID 阶段的 CSR 访问信号和数据 ——
    input  wire        csr_re,         // 读使能（rd != x0 时）
    input  wire        csr_we,         // 写使能（按 csr_op 决定）
    input  wire [11:0] csr_addr,       // 来自 instr[31:20]
    input  wire [31:0] csr_wdata,      // 写入数据（已经在外面算好：RW/RS/RC）
    output reg  [31:0] csr_rdata,      // 读出旧值（组合逻辑）

    // —— 来自 trap_ctrl 的 trap/mret 信号和相关数据 ——
    input  wire        trap_taken,     // 本拍发生 trap
    input  wire [31:0] trap_pc,        // 写入 mepc 的 PC（=触发 trap 的指令 PC）
    input  wire [31:0] trap_cause,     // 写入 mcause
    input  wire        mret_taken,     // 本拍发生 mret

    // —— 给取指 / trap_ctrl 看的当前值 ——
    output wire [31:0] mtvec_o,             
    output wire [31:0] mepc_o,
    output wire [31:0] mstatus_o
);

  // --- mstatus 关键字段 ---
  reg        mstatus_mie;   // bit 3
  reg        mstatus_mpie;  // bit 7
  reg [1:0]  mstatus_mpp;   // bit 12:11

  // --- 其他 CSR ---
  reg [31:0] mtvec_reg;      
  reg [31:0] mepc_reg;
  reg [31:0] mcause_reg;
  reg [31:0] mscratch_reg;     // 无字段约束，纯 32-bit 软件读写

  // ============ 读口（组合逻辑） ============
  always @(*) begin
    case (csr_addr)
      `CSR_MSTATUS : csr_rdata = {19'd0, mstatus_mpp, 3'd0,
                                  mstatus_mpie, 3'd0, mstatus_mie, 3'd0};
      `CSR_MTVEC   : csr_rdata = mtvec_reg;
      `CSR_MSCRATCH: csr_rdata = mscratch_reg;
      `CSR_MEPC    : csr_rdata = mepc_reg;
      `CSR_MCAUSE  : csr_rdata = mcause_reg;
      default      : csr_rdata = 32'h0;
    endcase
  end

  assign mtvec_o   = mtvec_reg;     // 直接输出 mtvec 寄存器值，供取指阶段使用
  assign mepc_o    = mepc_reg;      // 直接输出 mepc 寄存器值，供 trap_ctrl 使用
  assign mstatus_o = {19'd0, mstatus_mpp, 3'd0,
                      mstatus_mpie, 3'd0, mstatus_mie, 3'd0};

  // ============ 写口（同步逻辑，优先级：trap > mret > 软件） ============
  always @(posedge clk) begin
    if (rst) begin
      mstatus_mie  <= 1'b0;
      mstatus_mpie <= 1'b0;
      mstatus_mpp  <= 2'b11;   // 复位处在 M 模式
      mtvec_reg    <= 32'h0;
      mepc_reg     <= 32'h0;
      mcause_reg   <= 32'h0;
      mscratch_reg <= 32'h0;
    end else if (trap_taken) begin
      // 硬件 trap 副作用
      mepc_reg     <= {trap_pc[31:2], 2'b00};  // PC 对齐
      mcause_reg   <= trap_cause;
      mstatus_mpie <= mstatus_mie;
      mstatus_mie  <= 1'b0;
      mstatus_mpp  <= 2'b11;
    end else if (mret_taken) begin
      // mret 副作用：MPIE→MIE，MPIE 置 1
      mstatus_mie  <= mstatus_mpie;
      mstatus_mpie <= 1'b1;
    end else if (csr_we) begin
      case (csr_addr)
        `CSR_MSTATUS: begin
          mstatus_mie  <= csr_wdata[3];
          mstatus_mpie <= csr_wdata[7];
          mstatus_mpp  <= csr_wdata[12:11];
        end
        `CSR_MTVEC   : mtvec_reg    <= {csr_wdata[31:2], 2'b00};   // 仅支持 Direct
        `CSR_MSCRATCH: mscratch_reg <= csr_wdata;
        `CSR_MEPC    : mepc_reg     <= {csr_wdata[31:2], 2'b00};   // 4 字节对齐
        `CSR_MCAUSE  : mcause_reg   <= csr_wdata;
        default      : ;
      endcase
    end
  end

endmodule
