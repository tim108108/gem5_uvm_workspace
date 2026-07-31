class uvm_gem5_env extends uvm_env;
    `uvm_component_utils(uvm_gem5_env)

    trace_monitor       mon;
    uvm_gem5_scoreboard scb;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = trace_monitor::type_id::create("mon", this);
        scb = uvm_gem5_scoreboard::type_id::create("scb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        mon.mon_ap.connect(scb.scoreboard_port);
    endfunction
endclass
