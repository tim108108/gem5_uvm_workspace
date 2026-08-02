class test_hello extends uvm_test;
    `uvm_component_utils(test_hello)

    uvm_gem5_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = uvm_gem5_env::type_id::create("env", this);
        `uvm_info("BUILD", "UVM test_hello building...", UVM_LOW)
    endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info("RUN", "UVM test running, DPI-C comparison active...", UVM_LOW)
        wait (tb_top.uvm_diff_done.triggered);
        `uvm_info("RUN", "UVM diff comparison done, checking results...", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass
