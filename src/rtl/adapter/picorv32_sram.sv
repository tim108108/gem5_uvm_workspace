module picorv32_sram #(
    parameter DEPTH = 8192,
    parameter INIT_FILE = ""
) (
    input clk,
    input mem_valid,
    input mem_instr,
    output reg mem_ready,
    input [31:0] mem_addr,
    input [31:0] mem_wdata,
    input [ 3:0] mem_wstrb,
    output reg [31:0] mem_rdata
);

reg [7:0] mem_bytes [0:DEPTH*4-1];

import "DPI-C" function string dpi_get_hex_path();

initial begin
    automatic string init_path;
    if (INIT_FILE != "") begin
        init_path = INIT_FILE;
    end else begin
        init_path = dpi_get_hex_path();
    end
    if (init_path != "") begin
        $readmemh(init_path, mem_bytes);
        $display("[SRAM] Loaded %s, first bytes: %02x %02x %02x %02x",
            init_path, mem_bytes[0], mem_bytes[1], mem_bytes[2], mem_bytes[3]);
    end
end

wire [31:0] addr_byte = mem_addr & 32'hffff_ffff;

always @(posedge clk) begin
    mem_ready <= 0;
    if (mem_valid && !mem_ready) begin
        if (mem_wstrb[0]) mem_bytes[addr_byte + 0] <= mem_wdata[7:0];
        if (mem_wstrb[1]) mem_bytes[addr_byte + 1] <= mem_wdata[15:8];
        if (mem_wstrb[2]) mem_bytes[addr_byte + 2] <= mem_wdata[23:16];
        if (mem_wstrb[3]) mem_bytes[addr_byte + 3] <= mem_wdata[31:24];
        mem_rdata <= {mem_bytes[addr_byte + 3],
                      mem_bytes[addr_byte + 2],
                      mem_bytes[addr_byte + 1],
                      mem_bytes[addr_byte + 0]};
        mem_ready <= 1;
    end
end

endmodule
