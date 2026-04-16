/* `include "../include/defines.vh"
module forward_unit (
    input  wire [31:0] instr_ex,
    input  wire [31:0] instr_mem,
    input  wire        reg_we_mem,
    input  wire        mem_re_mem,
    input  wire [31:0] instr_wb,
    input  wire        reg_we_wb,
    input  wire [31:0] instr_id,

    output reg  [1:0]  fwd_a,
    output reg  [1:0]  fwd_b,
    output reg  [1:0]  fwd_br_a,    //拓展为两位，支持 EX/MEM 和 MEM/WB 前递到 BranchComp
    output reg  [1:0]  fwd_br_b    
);


    //提取各阶段指令寄存器地址
wire [4:0]  rs1_ex = instr_ex[19:15];
wire [4:0]  rs2_ex = instr_ex[24:20];
wire [4:0]  rd_mem = instr_mem[11:7];
wire [4:0]  rd_wb  = instr_wb[11:7];
wire [4:0]  rs1_id = instr_id[19:15];
wire [4:0]  rs2_id = instr_id[24:20];


//ALU A 前递 优先处理EX/MEM冒险
always @(*) begin
    if (reg_we_mem && (rd_mem != 5'd0) && (rd_mem == rs1_ex) && !mem_re_mem) begin
        fwd_a = `FWD_M;  //FWD_M=01（EX/MEM）
    end else if (reg_we_wb && (rd_wb != 5'd0) && (rd_wb == rs1_ex)) begin
        fwd_a = `FWD_W;  //FWD_W=10（MEM/WB）
    end else begin
        fwd_a = `FWD_NONE;  //FWD_NONE=00
    end
end

//ALU B 前递 优先处理EX/MEM冒险
always @(*) begin
    if (reg_we_mem && (rd_mem != 5'd0) && (rd_mem == rs2_ex) && !mem_re_mem) begin
        fwd_b = `FWD_M;  //FWD_M=01（EX/MEM）
    end else if (reg_we_wb && (rd_wb != 5'd0) && (rd_wb == rs2_ex)) begin
        fwd_b = `FWD_W;  //FWD_W=10（MEM/WB）
    end else begin
        fwd_b = `FWD_NONE;  //FWD_NONE=00
    end
end

//BranchComp rs1 前递  仅支持 EX/MEM→ID
always @(*) begin
    if (reg_we_mem && (rd_mem != 5'd0) && (rd_mem == rs1_id) && !mem_re_mem)
        fwd_br_a = 2'b01;  // from EX/MEM
    else if (reg_we_wb && (rd_wb != 5'd0) && (rd_wb == rs1_id))
        fwd_br_a = 2'b10;  // from MEM/WB
    else
        fwd_br_a = 2'b00;
end

//BranchComp rs2 前递  仅支持 EX/MEM→ID
always @(*) begin
    if (reg_we_mem && (rd_mem != 5'd0) && (rd_mem == rs2_id) && !mem_re_mem)
        fwd_br_b = 2'b01;  // from EX/MEM
    else if (reg_we_wb && (rd_wb != 5'd0) && (rd_wb == rs2_id))
        fwd_br_b = 2'b10;  // from MEM/WB
    else
        fwd_br_b = 2'b00;
end
endmodule */

`include "../include/defines.vh"

module forward_unit (
    input  wire [31:0] instr_ex,    // EX 级指令（当前计算的指令）
    input  wire [31:0] instr_mem,   // MEM 级指令（领先一拍的指令）
    input  wire        reg_we_mem,  // MEM 级写使能
    input  wire        mem_re_mem,  // MEM 级读使能（Load 指令标志）
    input  wire [31:0] instr_wb,    // WB 级指令（领先两拍的指令）
    input  wire        reg_we_wb,   // WB 级写使能

    output reg  [1:0]  fwd_a,       // 控制 ALU 输入 A 的选择
    output reg  [1:0]  fwd_b        // 控制 ALU 输入 B 的选择
);

    // 1. 字段提取
    wire [4:0] rs1_ex = instr_ex[19:15];
    wire [4:0] rs2_ex = instr_ex[24:20];
    wire [4:0] rd_mem = instr_mem[11:7];
    wire [4:0] rd_wb  = instr_wb[11:7];

    // 2. ALU A 端口前递逻辑
    always @(*) begin
        // 优先处理距离最近的冒险（EX/MEM 冒险）
        // 注意：如果是 Load 指令在 MEM 级，由于数据还没读出来，不能前递（由 Hazard Unit 处理 Stall）
        if (reg_we_mem && (rd_mem != 5'd0) && (rd_mem == rs1_ex) && !mem_re_mem) begin
            fwd_a = `FWD_M;      // 从 EX/MEM 寄存器前递
        end 
        // 处理较远的冒险（MEM/WB 冒险）
        else if (reg_we_wb && (rd_wb != 5'd0) && (rd_wb == rs1_ex)) begin
            fwd_a = `FWD_W;      // 从 MEM/WB 寄存器前递
        end 
        else begin
            fwd_a = `FWD_NONE;   // 不前递，使用原始寄存器值
        end
    end

    // 3. ALU B 端口前递逻辑
    always @(*) begin
        if (reg_we_mem && (rd_mem != 5'd0) && (rd_mem == rs2_ex) && !mem_re_mem) begin
            fwd_b = `FWD_M;      // 从 EX/MEM 寄存器前递
        end 
        else if (reg_we_wb && (rd_wb != 5'd0) && (rd_wb == rs2_ex)) begin
            fwd_b = `FWD_W;      // 从 MEM/WB 寄存器前递
        end 
        else begin
            fwd_b = `FWD_NONE;   // 不前递
        end
    end

endmodule