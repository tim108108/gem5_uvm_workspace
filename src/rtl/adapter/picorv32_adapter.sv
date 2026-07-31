module cpu_trace_adapter (
    input  logic        clk,
    input  logic        rvfi_valid,
    input  logic [31:0] rvfi_pc_rdata,
    input  logic [ 4:0] rvfi_rd_addr,
    input  logic [31:0] rvfi_rd_wdata,
    output logic        gen_commit_valid,
    output logic [63:0] gen_pc,
    output logic [ 5:0] gen_reg_addr,
    output logic [63:0] gen_reg_data
);
    assign gen_commit_valid = rvfi_valid;
    assign gen_pc           = {32'b0, rvfi_pc_rdata};
    assign gen_reg_addr     = {1'b0, rvfi_rd_addr};
    assign gen_reg_data     = {32'b0, rvfi_rd_wdata};
endmodule
