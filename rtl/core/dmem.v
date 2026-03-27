/* module dmem (
    input clk,
    input [31:0] alu_out,
    input [31:0] rs2,
    input mem_we,
    input mem_re,
    input [1:0] mem_width,
    input mem_sign,
    output reg [31:0] dmem_rdata
);

  reg [31:0] dmem[0:1023];

  always @(posedge clk) begin
    if (mem_we) begin
      case (mem_width)
        2'b00:   begin  //// SB：写入字节，保留其余三字
            case (alu_out[1:0])
            2'b00: dmem[alu_out[11:2]][7:0]   <= rs2[7:0];
            2'b01: dmem[alu_out[11:2]][15:8]  <= rs2[7:0];
            2'b10: dmem[alu_out[11:2]][23:16] <= rs2[7:0];
            2'b11: dmem[alu_out[11:2]][31:24] <= rs2[7:0];
          endcase
        end
        

        2'b01:   begin
            case (alu_out[1])
            1'b0: dmem[alu_out[11:2]][15:0]  <= rs2[15:0];
            1'b1: dmem[alu_out[11:2]][31:16] <= rs2[15:0];
          endcase 
        end

        2'b10:   dmem[alu_out[11:2]] <= rs2;  // SW
        default: ;
      endcase
    end
  end


  always @(*) begin //组合逻辑使用阻塞赋值 =，并加 default 防 latch
    if (mem_re) begin
      case (mem_width)
        2'b00:
        dmem_rdata = mem_sign ? {{24{dmem[alu_out[11:2]][7]}}, dmem[alu_out[11:2]][7:0]} : {24'b0, dmem[alu_out[11:2]][7:0]}; // LB/LBU
        2'b01:
        dmem_rdata = mem_sign ? {{16{dmem[alu_out[11:2]][15]}}, dmem[alu_out[11:2]][15:0]} : {16'b0, dmem[alu_out[11:2]][15:0]}; // LH/LHU
        2'b10: dmem_rdata = dmem[alu_out[11:2]];  // LW
        default: 
        dmem_rdata = 32'h0; // default case 防止 latch
      endcase
    end
  end
endmodule
*/

AI修复：
`include "../include/defines.vh"

module dmem (
    input  wire        clk,
    input  wire [31:0] alu_out,   // 访存地址 (即 ALU 结算出的目标地址)
    input  wire [31:0] rs2,       // Store 准备写入的数据
    input  wire        mem_we,    // 写使能
    input  wire        mem_re,    // 读使能
    input  wire [1:0]  mem_width, // 访存宽度 (`MEM_BYTE, `MEM_HALF, `MEM_WORD)
    input  wire        mem_sign,  // Load 符号扩展标志 (1: 有符号, 0: 无符号)
    output reg  [31:0] mem_rdata  // Load 最终输出的读取数据
);

    // ── 定义 4KB 内存，按 32-bit 字寻址 (1024 x 32) ──
    reg [31:0] mem [0:1023]; 

    // 提取出实际的字地址 (忽略最低两位字节偏移)
    wire [9:0] word_addr = alu_out[11:2];

    // ════════════════════════════════════════════════════════
    // 1. 同步写逻辑 (Write Mask + 组合数据对齐)
    // ════════════════════════════════════════════════════════
    reg [3:0]  write_mask;
    reg [31:0] aligned_wdata;

    always @(*) begin
        write_mask = 4'b0000;
        aligned_wdata = 32'b0;

        if (mem_we) begin
            case (mem_width)
                `MEM_BYTE: begin // SB 指令
                    // 根据地址低两位生成单字节使能信号
                    write_mask = 4'b0001 << alu_out[1:0];
                    // 将低 8 位数据复制 4 份，靠 mask 决定把哪一份写进 BRAM
                    aligned_wdata = {4{rs2[7:0]}}; 
                end
                `MEM_HALF: begin // SH 指令
                    // 根据地址 bit[1] 决定写高半字还是低半字
                    write_mask = alu_out[1] ? 4'b1100 : 4'b0011;
                    aligned_wdata = {2{rs2[15:0]}}; 
                end
                `MEM_WORD: begin // SW 指令
                    write_mask = 4'b1111;
                    aligned_wdata = rs2;
                end
                default: begin
                    write_mask = 4'b0000;
                    aligned_wdata = 32'b0;
                end
            endcase
        end
    end

    // 标准的字节使能 BRAM 写入格式 (综合器最喜欢的写法)
    always @(posedge clk) begin
        if (write_mask[0]) mem[word_addr][7:0]   <= aligned_wdata[7:0];
        if (write_mask[1]) mem[word_addr][15:8]  <= aligned_wdata[15:8];
        if (write_mask[2]) mem[word_addr][23:16] <= aligned_wdata[23:16];
        if (write_mask[3]) mem[word_addr][31:24] <= aligned_wdata[31:24];
    end

    // ════════════════════════════════════════════════════════
    // 2. 异步组合读逻辑 (处理 Latch 与符号扩展)
    // ════════════════════════════════════════════════════════
    wire [31:0] raw_word = mem[word_addr];
    reg  [7:0]  byte_out;
    reg  [15:0] half_out;

    // 截取需要的 Byte
    always @(*) begin
        case (alu_out[1:0])
            2'b00: byte_out = raw_word[7:0];
            2'b01: byte_out = raw_word[15:8];
            2'b10: byte_out = raw_word[23:16];
            2'b11: byte_out = raw_word[31:24];
        endcase
    end

    // 截取需要的 Half-word
    always @(*) begin
        case (alu_out[1])
            1'b0: half_out = raw_word[15:0];
            1'b1: half_out = raw_word[31:16];
        endcase
    end

    // 选择并执行符号扩展 (防 Latch 写法)
    always @(*) begin
        mem_rdata = 32'h0; // 给定默认值，彻底杜绝 Latch
        if (mem_re) begin
            case (mem_width)
                `MEM_BYTE: mem_rdata = mem_sign ? {{24{byte_out[7]}}, byte_out}  : {24'h0, byte_out};
                `MEM_HALF: mem_rdata = mem_sign ? {{16{half_out[15]}}, half_out} : {16'h0, half_out};
                `MEM_WORD: mem_rdata = raw_word;
                default:   mem_rdata = raw_word;
            endcase
        end
    end

endmodule