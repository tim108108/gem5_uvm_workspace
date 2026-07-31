class test_hello extends uvm_test;
    `uvm_component_utils(test_hello)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("BUILD", "UVM test_hello building...", UVM_LOW)
    endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("RUN", "UVM test running, DPI-C comparison active...", UVM_LOW)
        wait (tb_top.done);
        `uvm_info("RUN", "UVM test done, checking results...", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass
