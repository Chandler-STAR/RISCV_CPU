`include "defines.vh"

module regfile(
    input clk,
    input [4:0] rs1_addr,
    input [4:0] rs2_addr,
    input [4:0] rd_addr,
    input [31:0] wd,
    input reg_we,
    output reg [31:0] rs1_rf,
    output reg [31:0] rs2_rf
);

    x0 = 0; // x0寄存器始终为0
    //异步读
    assign rs1 = (rs1_addr == 5'd0) ? 32'd0 : rf[rs1_addr];// 读寄存器1，x0寄存器始终为0
    assign rs2 = (rs2_addr == 5'd0) ? 32'd0 : rf[rs2_addr];// 读寄存器2，x0寄存器始终为0


    //同步写    x0寄存器始终为0，写入x0寄存器的操作被忽略
    always @(posedge clk) begin
        if (reg_we && rd_addr != 5'd0)
            rf[rd_addr] <= wd;
    end
endmodule