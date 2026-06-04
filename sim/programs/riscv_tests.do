# ============================================================================
# Batch run riscv-tests for the current RV32 core.
# Runs rv32ui and rv32um .dat images, then reports PASS/FAIL/HANG.
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

set TESTS_DIR ../../tests/unofficial_test_data
set tests {}
foreach pattern {rv32ui-p-*.dat rv32um-p-*.dat} {
    foreach test [glob -nocomplain "$TESTS_DIR/$pattern"] {
        lappend tests $test
    }
}
set tests [lsort $tests]

set pass_list {}
set fail_list {}
set hang_list {}

echo "================================================================"
echo "Running [llength $tests] riscv-tests..."
echo "================================================================"

foreach test $tests {
    set name [file rootname [file tail $test]]
    regsub {^rv32u[im]-p-} $name {} name_short

    vsim -onfinish stop \
         -gIROM_HEX=$test \
         -gDRAM_HEX=$TESTS_DIR/empty.dat \
         -gTEST_MODE=1 \
         -gMAX_CYCLES=200000 \
         tb_myCPU

    onbreak {resume}
    run -all

    set s10_str [examine -radix unsigned /tb_myCPU/u_cpu/u_regfile/rf\[26\]]
    set s11_str [examine -radix unsigned /tb_myCPU/u_cpu/u_regfile/rf\[27\]]
    set gp_str  [examine -radix unsigned /tb_myCPU/u_cpu/u_regfile/rf\[3\]]

    set s10 [lindex $s10_str end]
    set s11 [lindex $s11_str end]
    set gp  [lindex $gp_str end]

    if {$s10 == 1 && $s11 == 1} {
        echo "  PASS  $name_short"
        lappend pass_list $name
    } elseif {$s10 == 1 && $s11 == 0} {
        echo "  FAIL  $name_short  testnum=$gp"
        lappend fail_list "${name}/testnum=${gp}"
    } else {
        echo "  HANG  $name_short  s10=$s10 s11=$s11 gp=$gp"
        lappend hang_list "${name}/s10=${s10},s11=${s11},gp=${gp}"
    }

    quit -sim
}

echo ""
echo "================================================================"
echo "SUMMARY: [llength $pass_list] PASS, [llength $fail_list] FAIL, [llength $hang_list] HANG"
echo "================================================================"

if {[llength $fail_list] > 0} {
    echo ""
    echo "--- FAIL ---"
    foreach f $fail_list { echo "  $f" }
}
if {[llength $hang_list] > 0} {
    echo ""
    echo "--- HANG ---"
    foreach h $hang_list { echo "  $h" }
}

quit -f
