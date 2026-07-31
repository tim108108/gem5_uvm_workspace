interface cpu_trace_adapter_if;
    logic        clk;
    logic        gen_commit_valid;
    logic [63:0] gen_pc;
    logic [ 5:0] gen_reg_addr;
    logic [63:0] gen_reg_data;
endinterface
