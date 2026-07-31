import uvm_pkg::*;
`include "uvm_macros.svh"

import "DPI-C" function void dpi_gem5_init(string elf_path);
import "DPI-C" function int  dpi_gem5_step_and_compare(input bit [511:0] packed_commit);

class uvm_gem5_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(uvm_gem5_scoreboard)

    uvm_analysis_imp #(trace_transaction, uvm_gem5_scoreboard) scoreboard_port;

    string elf_path;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        scoreboard_port = new("scoreboard_port", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        dpi_gem5_init(elf_path);
    endfunction

    function void write(trace_transaction txn);
        int status;
        status = dpi_gem5_step_and_compare(txn.pack_to_dpi());
        if (status != 0) begin
            `uvm_error("DIFFTEST_MISMATCH",
                $sformatf("Mismatch at PC=0x%0h", txn.pc))
        end else begin
            `uvm_info("DIFFTEST_MATCH",
                $sformatf("PC=0x%0h OK", txn.pc), UVM_HIGH)
        end
    endfunction
endclass
