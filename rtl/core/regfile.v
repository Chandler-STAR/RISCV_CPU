`include "../include/defines.vh"

module regfile (
    input         clk,
    input  [4:0]  rs1_addr, 
    input  [4:0]  rs2_addr, 
    output [31:0] rs1,
    output [31:0] rs2,
    input  [4:0]  rd_addr,  
    input  [31:0] wd,       
    input         reg_we    
);
    reg [31:0] rf [0:31]; // 只需要定义 1-31，x0 逻辑由硬件保证
    //异步读
    assign rs1 = (rs1_addr == 5'd0) ? 32'd0 : rf[rs1_addr];// 读寄存器1，x0寄存器始终为0
    assign rs2 = (rs2_addr == 5'd0) ? 32'd0 : rf[rs2_addr];// 读寄存器2，x0寄存器始终为0


    //同步写    x0寄存器始终为0，写入x0寄存器的操作被忽略
    always @(posedge clk) begin
        if (reg_we && rd_addr != 5'd0)
            rf[rd_addr] <= wd;
    end
endmodule