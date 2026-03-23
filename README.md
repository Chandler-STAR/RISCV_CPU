# RISCV_CPU

RISC-V RV32I CPU core 

![微架构](https://github.com/Chandler-STAR/RISCV_CPU/blob/main/doc/img/%E5%BE%AE%E6%9E%B6%E6%9E%84.png)

![微架构1](https://github.com/Chandler-STAR/RISCV_CPU/blob/main/doc/img/%E5%BE%AE%E6%9E%B6%E6%9E%841.png)

## TODO

&#x26a0;&#xfe0f; bugfixing

&#x2705; done

&#x1f504; coding
>Example 
>
>When coding "defines.vh" ,type " &#x1f504;" in the state box.
>
>| defines.vh     | &#x1f504; |

| Module         | State     | Remark   |
| -------------- | --------- | -------- |
| defines.vh     | &#x1f504; |          |
| riscv_top.v    | &#x1f504; | 未编写tb |
| pc_reg.v       | &#x2705;  |          |
| imem.v         | &#x2705;  |          |
| if_id_reg.v    | &#x1f504; | 未编写tb |
| regfile.v      | &#x2705;  |          |
| imm_gen.v      | &#x1f504; | 未编写tb |
| branch_comp.v  | &#x1f504; | 未编写tb |
| ctrl.v         | &#x1f504; | 未编写tb |
| id_ex_reg.v    | &#x1f504; | 未编写tb |
| alu.v          | &#x1f504; | 未编写tb |
| ex_mem_reg.v   | &#x1f504; |          |
| dmem.v         |           |          |
| mem_wb_reg.v   |           |          |
| forward_unit.v |           |          |
| hazard_unit.v  |           |          |

## Reference

[RISC-V Reference](https://www.cs.sfu.ca/~ashriram/Courses/CS295/assets/notebooks/RISCV/RISCV_CARD.pdf)





<!-- * [ ] defines.vh    
* [ ] riscv_top.v
* [ ] pc_reg.v
* [ ] imem.v
* [ ] if_id_reg.v
* [ ] regfile.v
* [ ] imm_gen.v
* [ ] branch_comp.v
* [ ] ctrl.v
* [ ] id_ex_reg.v
* [ ] alu.v
* [ ] ex_mem_reg.v
* [ ] dmem.v
* [ ] mem_wb_reg.v
* [ ] forward_unit.v
* [ ] hazard_unit.v -->