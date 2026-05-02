`include "../include/defines.vh"

// 寄存器文件 —— 32x32bit，x0硬连线为0
module regfile (
    input  wire        clk,
    input  wire [ 4:0] rs1_addr,
    input  wire [ 4:0] rs2_addr,
    output wire [31:0] rs1_rf,
    output wire [31:0] rs2_rf,
    input  wire [ 4:0] rd_addr,
    input  wire [31:0] wd,
    input  wire        reg_we
);

    reg [31:0] rf [0:31];
    integer i;

    initial begin
        for (i = 0; i < 32; i = i + 1)
            rf[i] = 32'h0;
    end

    assign rs1_rf = (rs1_addr == 5'd0) ? 32'd0 : rf[rs1_addr];
    assign rs2_rf = (rs2_addr == 5'd0) ? 32'd0 : rf[rs2_addr];

    // posedge写入 (FPGA BRAM兼容)：WB→ID直通旁路在myCPU中处理
    always @(posedge clk) begin
        if (reg_we && rd_addr != 5'd0)
            rf[rd_addr] <= wd;
    end

endmodule
