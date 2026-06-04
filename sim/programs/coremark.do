# ============================================================================
# Questa / ModelSim run script for CoreMark on the RV32IM CPU.
# Run from sim/programs:
#   vsim -c -do coremark.do
# ============================================================================

catch { vdel -lib work -all }
vlib work

set INC ../../rtl/include

vlog -sv "+incdir+$INC" \
    ../../rtl/core/pc_reg.v \
    ../../rtl/core/imm_gen.v \
    ../../rtl/core/regfile.v \
    ../../rtl/core/ctrl.v \
    ../../rtl/core/alu.v \
    ../../rtl/core/mdu.v \
    ../../rtl/core/branch_comp.v \
    ../../rtl/core/branch_predictor.v \
    ../../rtl/core/csr_regfile.v \
    ../../rtl/core/trap_ctrl.v \
    ../../rtl/core/forward_unit.v \
    ../../rtl/core/hazard_unit.v \
    ../../rtl/core/if_id_reg.v \
    ../../rtl/core/id_ex1_reg.v \
    ../../rtl/core/ex1_ex2_reg.v \
    ../../rtl/core/ex2_mem1_reg.v \
    ../../rtl/core/mem1_mem2_reg.v \
    ../../rtl/core/mem2_wb_reg.v \
    ../../rtl/soc/myCPU.sv \
    ../../sim/tb/tb_myCPU/tb_myCPU.sv

set IHEX ../../tests/coremark/build/imem.hex
set DHEX ../../tests/coremark/build/dmem.hex

vsim -onfinish stop \
     -voptargs=+acc \
     -gIROM_HEX=$IHEX \
     -gDRAM_HEX=$DHEX \
     -gMAX_CYCLES=200000000 \
     tb_myCPU

run -all

echo "===== final dump from do script ====="
examine -radix unsigned tb_myCPU/u_cpu/perf_cycles
examine -radix unsigned tb_myCPU/u_cpu/perf_instret
examine -radix unsigned tb_myCPU/u_cpu/perf_branch_total
examine -radix unsigned tb_myCPU/u_cpu/perf_branch_mispred
examine -radix unsigned tb_myCPU/u_cpu/perf_jump_total
examine -radix unsigned tb_myCPU/u_cpu/perf_jump_mispred

quit -f
