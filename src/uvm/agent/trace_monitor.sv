class trace_monitor extends uvm_monitor;
    `uvm_component_utils(trace_monitor)

    uvm_analysis_port #(trace_transaction) mon_ap;

    virtual cpu_trace_adapter_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon_ap = new("mon_ap", this);
        if (!uvm_config_db #(virtual cpu_trace_adapter_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "No virtual interface set")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk);
            if (vif.gen_commit_valid) begin
                automatic trace_transaction txn = trace_transaction::type_id::create("txn");
                txn.pc           = vif.gen_pc;
                txn.reg_write_en = |vif.gen_reg_addr;
                txn.reg_addr     = vif.gen_reg_addr;
                txn.reg_data     = vif.gen_reg_data;
                `uvm_info("MONITOR", $sformatf("Commit: PC=0x%0h Reg[%0d]=0x%0h",
                    txn.pc, txn.reg_addr, txn.reg_data), UVM_HIGH)
                mon_ap.write(txn);
            end
        end
    endtask
endclass
