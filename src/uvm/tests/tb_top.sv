`define RISCV_FORMAL

module tb_top;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    event uvm_diff_done;

    reg clk = 0;
    reg resetn = 0;
    wire trap;
    integer cycle;

    always #5 clk = ~clk;

    initial begin
        repeat (10) @(posedge clk);
        resetn <= 1;
    end

    initial begin
        cycle = 0;
        @(posedge resetn);
        while (!trap) begin
            @(posedge clk);
            cycle = cycle + 1;
            if (cycle > 100000) begin
                $display("TIMEOUT after %0d cycles", cycle);
                $finish;
            end
        end
        repeat (10) @(posedge clk);
        $display("TRAP after %0d cycles", cycle);
        $finish;
    end

    wire        rvfi_valid;
    wire [63:0] rvfi_order;
    wire [31:0] rvfi_insn;
    wire        rvfi_trap;
    wire        rvfi_halt;
    wire        rvfi_intr;
    wire [ 1:0] rvfi_mode;
    wire [ 1:0] rvfi_ixl;
    wire [ 4:0] rvfi_rs1_addr;
    wire [ 4:0] rvfi_rs2_addr;
    wire [31:0] rvfi_rs1_rdata;
    wire [31:0] rvfi_rs2_rdata;
    wire [ 4:0] rvfi_rd_addr;
    wire [31:0] rvfi_rd_wdata;
    wire [31:0] rvfi_pc_rdata;
    wire [31:0] rvfi_pc_wdata;
    wire [31:0] rvfi_mem_addr;
    wire [ 3:0] rvfi_mem_rmask;
    wire [ 3:0] rvfi_mem_wmask;
    wire [31:0] rvfi_mem_rdata;
    wire [31:0] rvfi_mem_wdata;

    wire [3:0] mem_wstrb;
    wire mem_valid;
    wire mem_instr;
    wire mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [31:0] mem_rdata;
    wire [31:0] irq = 0;

    picorv32 #(
        .PROGADDR_RESET(32'h0000_0000),
        .STACKADDR(32'h0000_FFFF),
        .COMPRESSED_ISA(1),
        .ENABLE_MUL(1),
        .ENABLE_DIV(1),
        .ENABLE_IRQ(1),
        .ENABLE_TRACE(1)
    ) dut (
        .clk(clk),
        .resetn(resetn),
        .trap(trap),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .irq(irq),
        .rvfi_valid(rvfi_valid),
        .rvfi_order(rvfi_order),
        .rvfi_insn(rvfi_insn),
        .rvfi_trap(rvfi_trap),
        .rvfi_halt(rvfi_halt),
        .rvfi_intr(rvfi_intr),
        .rvfi_mode(rvfi_mode),
        .rvfi_ixl(rvfi_ixl),
        .rvfi_rs1_addr(rvfi_rs1_addr),
        .rvfi_rs2_addr(rvfi_rs2_addr),
        .rvfi_rs1_rdata(rvfi_rs1_rdata),
        .rvfi_rs2_rdata(rvfi_rs2_rdata),
        .rvfi_rd_addr(rvfi_rd_addr),
        .rvfi_rd_wdata(rvfi_rd_wdata),
        .rvfi_pc_rdata(rvfi_pc_rdata),
        .rvfi_pc_wdata(rvfi_pc_wdata),
        .rvfi_mem_addr(rvfi_mem_addr),
        .rvfi_mem_rmask(rvfi_mem_rmask),
        .rvfi_mem_wmask(rvfi_mem_wmask),
        .rvfi_mem_rdata(rvfi_mem_rdata),
        .rvfi_mem_wdata(rvfi_mem_wdata)
    );

    picorv32_sram #(
        .DEPTH(8192),
        .INIT_FILE("")
    ) sram (
        .clk(clk),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata)
    );

    cpu_trace_adapter_if vif();
    assign vif.clk = clk;
    assign vif.gen_commit_valid = rvfi_valid;
    assign vif.gen_pc           = {32'b0, rvfi_pc_rdata};
    assign vif.gen_reg_addr     = {1'b0, rvfi_rd_addr};
    assign vif.gen_reg_data     = {32'b0, rvfi_rd_wdata};

    initial begin
        uvm_config_db #(virtual cpu_trace_adapter_if)::set(null, "*.env.mon", "vif", vif);
        run_test("test_hello");
    end
endmodule
