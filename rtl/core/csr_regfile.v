`include "../include/defines.vh"
// CSR寄存器堆(CSR = Control and Status Register,控制与状态寄存器),M模式
// 属于Zicsr扩展:Z=标准扩展前缀,i=整数(integer),csr=CSR访问指令,
// 共6条:csrrw/csrrs/csrrc + 立即数版csrrwi/csrrsi/csrrci(都是I型,CSR地址占立即数位)
//
// 本核实现的CSR:
//   mstatus  0x300  状态寄存器,只实现MIE/MPIE/MPP三个字段(字段含义见下面声明处)
//   mtvec    0x305  trap入口地址,类似8086的中断向量表,但只有一个入口,进门靠mcause分诊
//   mscratch 0x340  无硬件含义的白板,留给trap处理程序的"第33个寄存器"
//   mepc     0x341  出事指令的PC,mret原样跳回(ecall要软件先+4再mret,否则死循环)
//   mcause   0x342  出的什么事:最高位区分中断(1,异步)/异常(0,同步),低位是原因码
//   mcycle/minstret 0xB00/0xB02  周期/指令计数器,64位拆成高低两半;
//                   cycle/instret(0xC00/0xC02)等只读影子地址读的是同一份计数器

module csr_regfile (
    input  wire        clk,
    input  wire        rst,

    // —— 来自 ID 阶段的 CSR 访问信号和数据 ——
    input  wire        csr_we,         // 写使能(已在核内打过一拍,寄存器源)
    input  wire [11:0] csr_addr,       // 读地址:来自 instr[31:20]
    input  wire [11:0] csr_waddr,      // 写地址:与写数据同拍寄存(读写口分离)
    input  wire [31:0] csr_wdata,      // 写入数据（已经在外面算好并打拍：RW/RS/RC）
    output reg  [31:0] csr_rdata,      // 读出旧值（组合逻辑）

    // —— 来自 trap_ctrl 的 trap/mret 信号和相关数据 ——
    input  wire        trap_taken,     // 本拍发生 trap
    input  wire [31:0] trap_pc,        // 写入 mepc 的 PC（=触发 trap 的指令 PC）
    input  wire [31:0] trap_cause,     // 写入 mcause
    input  wire        mret_taken,     // 本拍发生 mret

    // —— 性能计数器 ——
    input  wire        instret_inc,    // 这一拍有1条指令完成写回
    input  wire        instret_dbl,    // 本拍完成的是融合指令(两条熔成的),计数要+2

    // —— 给取指 / trap_ctrl 看的当前值 ——
    output wire [31:0] mtvec_o,
    output wire [31:0] mepc_o
);

  // --- mstatus 关键字段 ---
  reg        mstatus_mie;   // bit3  MIE:中断总开关,=1允许中断。trap时挪到MPIE并清0
                            //       (单寄存器不是栈,嵌套trap会丢现场,所以处理期间必须关)
  reg        mstatus_mpie;  // bit7  MPIE:trap时MIE的寄存处,mret时再挪回MIE
  reg [1:0]  mstatus_mpp;   // bit12:11 MPP:trap前的特权级(M/S/U),mret按它跳回原圈层;
                            //       本核只有M模式,恒2'b11

  // --- 其他 CSR ---
  reg [31:0] mtvec_reg;        // trap入口地址,trap时装进PC;低2位强制0(只支持Direct单入口)
  reg [31:0] mepc_reg;         // 出事指令的PC。ecall返回前软件要自己把它+4;低2位强制0对齐
  reg [31:0] mcause_reg;       // 最高位:中断1/异常0;低位原因码。本核只有ecall from M,写11
  reg [31:0] mscratch_reg;     // 软件白板,惯用 csrrw sp,mscratch,sp 一条指令换出备用栈指针

  // --- 性能计数器：低/高 32 位拆开，进位打 1 拍，断开 64 位长进位链以提频 ---
  // 高半字比低半字回绕晚 1 拍更新（每 2^32 次仅 1 拍内 {hi,lo} 偏差 2^32；测试 <2^32，无影响）
  reg [31:0] mcycle_lo,   mcycle_hi;
  reg [31:0] minstret_lo, minstret_hi;
  reg        mcycle_cy,   minstret_cy;   // 低半字本拍回绕 → 下一拍高半字 +1

  // ============ 读口（组合逻辑） ============
  always @(*) begin
    case (csr_addr)
      `CSR_MSTATUS : csr_rdata = {19'd0, mstatus_mpp, 3'd0,
                                  mstatus_mpie, 3'd0, mstatus_mie, 3'd0};
      `CSR_MTVEC   : csr_rdata = mtvec_reg;
      `CSR_MSCRATCH: csr_rdata = mscratch_reg;
      `CSR_MEPC    : csr_rdata = mepc_reg;
      `CSR_MCAUSE  : csr_rdata = mcause_reg;
      `CSR_MCYCLE,    `CSR_CYCLE   : csr_rdata = mcycle_lo;
      `CSR_MCYCLEH,   `CSR_CYCLEH  : csr_rdata = mcycle_hi;
      `CSR_MINSTRET,  `CSR_INSTRET : csr_rdata = minstret_lo;
      `CSR_MINSTRETH, `CSR_INSTRETH: csr_rdata = minstret_hi;
      default      : csr_rdata = 32'h0;
    endcase
  end

  assign mtvec_o   = mtvec_reg;     // 直接输出 mtvec 寄存器值，供取指阶段使用
  assign mepc_o    = mepc_reg;      // 直接输出 mepc 寄存器值，供 trap_ctrl 使用

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
      case (csr_waddr)
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

  // ============ 性能计数器 ============
  // 64位直接{hi,lo}+1进位链太长拖主频,学里程表拆两半:低半每拍+1,
  // 到头只记个进位旗,高半下一拍才+1(那一拍读数小2^32,每43亿拍1次,碰不到)。
  // 没做软件写口,csrw写不进(省掉csr_wdata深路径;计时走CNT外设),rdcycle读正常。
  // minstret进位两种情况:lo=全F,或lo=全F-1且本次+2(融合指令)。
  always @(posedge clk) begin
    if (rst) begin
      mcycle_lo   <= 32'd0; mcycle_hi   <= 32'd0; mcycle_cy   <= 1'b0;
      minstret_lo <= 32'd0; minstret_hi <= 32'd0; minstret_cy <= 1'b0;
    end else begin
      // ---- mcycle：每拍 +1 ----
      mcycle_lo <= mcycle_lo + 32'd1;
      mcycle_hi <= mcycle_hi + {31'd0, mcycle_cy};
      mcycle_cy <= (mcycle_lo == 32'hFFFF_FFFF);
      // ---- minstret：instret_inc 时 +1(熔合对 +2)----
      minstret_lo <= instret_inc ? (minstret_lo + (instret_dbl ? 32'd2 : 32'd1)) : minstret_lo;
      minstret_hi <= minstret_hi + {31'd0, minstret_cy};
      minstret_cy <= instret_inc && ((minstret_lo == 32'hFFFF_FFFF)
                                  || (instret_dbl && (minstret_lo == 32'hFFFF_FFFE)));
    end
  end

endmodule
