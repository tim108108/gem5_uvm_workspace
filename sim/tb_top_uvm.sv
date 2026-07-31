`define RISCV_FORMAL

module tb_top;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

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
    wire [31:0] rvfi_insn;
    wire        rvfi_trap;
    wire [ 4:0] rvfi_rd_addr;
    wire [31:0] rvfi_rd_wdata;
    wire [31:0] rvfi_pc_rdata;

    wire mem_valid, mem_instr, mem_ready;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0]  mem_wstrb;
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
        .clk(clk), .resetn(resetn), .trap(trap),
        .mem_valid(mem_valid), .mem_instr(mem_instr),
        .mem_ready(mem_ready), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata), .irq(irq),
        .rvfi_valid(rvfi_valid), .rvfi_insn(rvfi_insn),
        .rvfi_trap(rvfi_trap),
        .rvfi_rd_addr(rvfi_rd_addr), .rvfi_rd_wdata(rvfi_rd_wdata),
        .rvfi_pc_rdata(rvfi_pc_rdata)
    );

    picorv32_sram #(
        .DEPTH(8192),
        .INIT_FILE("/workspace/gem5_uvm_workspace/sw/custom_tests/test_add.hex")
    ) sram (
        .clk(clk), .mem_valid(mem_valid), .mem_instr(mem_instr),
        .mem_ready(mem_ready), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata)
    );

    // DPI-C import for comparison
    import "DPI-C" function void dpi_gem5_init(input string trace_path);
    import "DPI-C" function int dpi_gem5_step_and_compare(
        input longint unsigned pc,
        input byte we,
        input byte ra,
        input longint unsigned rd
    );

    reg done = 0;

    initial begin
        dpi_gem5_init("/workspace/gem5_uvm_workspace/sim/traces/test_add.trace");
        #1;
    end

    always @(posedge clk) begin
        if (rvfi_valid) begin
            automatic int result;
            result = dpi_gem5_step_and_compare(
                rvfi_pc_rdata,
                (rvfi_rd_addr != 0) ? 8'd1 : 8'd0,
                rvfi_rd_addr,
                rvfi_rd_wdata
            );
            if (result != 0) begin
                $display("[UVM] MISMATCH at PC=0x%08x time=%0t", rvfi_pc_rdata, $time);
                done = 1;
                #100 $finish;
            end
        end
    end
endmodule
