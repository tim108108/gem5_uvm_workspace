`define RISCV_FORMAL

module tb_top;
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

    always @(posedge clk) begin
        if (rvfi_valid)
            $display("RVFI: PC=0x%08x insn=0x%08x rd=%d rd_data=0x%08x trap=%d",
                rvfi_pc_rdata, rvfi_insn, rvfi_rd_addr, rvfi_rd_wdata, rvfi_trap);
    end
endmodule
