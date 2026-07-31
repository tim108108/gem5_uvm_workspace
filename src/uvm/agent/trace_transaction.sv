class trace_transaction extends uvm_sequence_item;
    `uvm_object_utils(trace_transaction)

    rand bit [63:0] pc;
    rand bit [31:0] instr;
    rand bit        reg_write_en;
    rand bit [ 5:0] reg_addr;
    rand bit [63:0] reg_data;
    rand bit        is_mem_op;
    rand bit [63:0] mem_addr;

    function new(string name = "trace_transaction");
        super.new(name);
    endfunction

    function bit [511:0] pack_to_dpi();
        automatic bit [511:0] result = 0;
        result[63:0]    = pc;
        result[95:64]   = instr;
        result[96]      = reg_write_en;
        result[102:97]  = reg_addr;
        result[166:103] = reg_data;
        result[167]     = is_mem_op;
        result[231:168] = mem_addr;
        return result;
    endfunction
endclass
