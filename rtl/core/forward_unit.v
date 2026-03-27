`include "../include/defines.vh"
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
endmodule