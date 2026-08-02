import uvm_pkg::*;
import dpi_bridge_pkg::*;
`include "uvm_macros.svh"

class uvm_gem5_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(uvm_gem5_scoreboard)

    uvm_analysis_imp #(trace_transaction, uvm_gem5_scoreboard) scoreboard_port;

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        scoreboard_port = new("scoreboard_port", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        dpi_gem5_init(dpi_get_trace_path());
        `uvm_info("SCOREBOARD", "Golden trace loaded via DPI-C", UVM_LOW)
    endfunction

    function void write(trace_transaction txn);
        automatic int status;
        status = dpi_gem5_step_and_compare(
            txn.pc,
            txn.reg_write_en,
            txn.reg_addr,
            txn.reg_data
        );
        if (status != 0) begin
            fail_cnt = fail_cnt + 1;
            `uvm_error("DIFFTEST_MISMATCH",
                $sformatf("Mismatch at PC=0x%0h", txn.pc))
        end else begin
            pass_cnt = pass_cnt + 1;
            `uvm_info("DIFFTEST_MATCH",
                $sformatf("PC=0x%0h OK", txn.pc), UVM_HIGH)
        end
        if (pass_cnt + fail_cnt >= dpi_total_entries()) begin
            if (fail_cnt == 0) begin
                $display("[UVM Scoreboard] PASS: %0d / %0d entries matched", pass_cnt, pass_cnt + fail_cnt);
            end else begin
                $display("[UVM Scoreboard] FAIL: %0d pass, %0d fail out of %0d entries", pass_cnt, fail_cnt, pass_cnt + fail_cnt);
            end
            -> tb_top.uvm_diff_done;
        end
    endfunction
endclass
