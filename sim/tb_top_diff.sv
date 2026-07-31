`define RISCV_FORMAL

module tb_top;
    import dpi_bridge_pkg::*;

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
        .INIT_FILE("")
    ) sram (
        .clk(clk), .mem_valid(mem_valid), .mem_instr(mem_instr),
        .mem_ready(mem_ready), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata)
    );

    // DiffTest: compare RVFI against golden trace
    integer cmp_pass = 0;
    integer cmp_fail = 0;

    import "DPI-C" function string dpi_get_trace_path();
    import "DPI-C" function int dpi_total_entries();

    initial begin
        dpi_gem5_init(dpi_get_trace_path());
        $display("[DiffTest] Golden trace loaded, starting RTL comparison...");
    end

    integer total = 0;
    integer rvfi_count = 0;

    always @(posedge clk) begin
        if (rvfi_valid) begin
            automatic int result;
            result = dpi_gem5_step_and_compare(
                rvfi_pc_rdata,
                (rvfi_rd_addr != 0) ? 8'd1 : 8'd0,
                rvfi_rd_addr,
                rvfi_rd_wdata
            );
            rvfi_count = rvfi_count + 1;
            if (result != 0) begin
                cmp_fail = cmp_fail + 1;
                $display("[DiffTest FAIL] entry %0d PC=0x%08x", cmp_pass + cmp_fail - 1, rvfi_pc_rdata);
            end else begin
                cmp_pass = cmp_pass + 1;
            end
            total = dpi_total_entries();
            if (cmp_pass + cmp_fail >= total) begin
                if (cmp_fail == 0) begin
                    $display("[DiffTest] PASS: %0d / %0d entries matched, %0d RVFI events", cmp_pass, cmp_pass + cmp_fail, rvfi_count);
                end else begin
                    $display("[DiffTest] FAIL: %0d pass, %0d fail out of %0d entries", cmp_pass, cmp_fail, cmp_pass + cmp_fail);
                end
                $finish;
            end
        end
    end

    initial begin
        #2000;
        if (cmp_fail == 0) begin
            $display("[DiffTest] PASS: %0d / %0d entries matched, %0d RVFI events", cmp_pass, cmp_pass + cmp_fail, rvfi_count);
        end else begin
            $display("[DiffTest] FAIL: %0d pass, %0d fail (timeout)", cmp_pass, cmp_fail);
        end
        $finish;
    end
endmodule
