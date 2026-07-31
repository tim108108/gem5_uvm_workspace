`ifndef __DPI_BRIDGE_PKG_SV
`define __DPI_BRIDGE_PKG_SV

package dpi_bridge_pkg;

    import "DPI-C" function void dpi_gem5_init(input string trace_path);

    import "DPI-C" function string dpi_get_trace_path();

    import "DPI-C" function int dpi_gem5_step_and_compare(
        input longint unsigned pc,
        input byte we,
        input byte ra,
        input longint unsigned rd
    );

    import "DPI-C" function int dpi_total_entries();

endpackage

`endif
