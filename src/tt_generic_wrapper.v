/*
 * tt_um_rte_sine_synth_wrapper.v - Modified for consistent clocking
 *
 * Wrapper for Arty A7 board around the
 * TinyTapeout project tt_um_qspi_matrix_mult.v
 *
 * Changes:
 * (1) Removed clock halving. Project runs at full system clock speed.
 * (2) Simplified reset handling (project uses active-low directly).
 * (3) Retained bidirectional pin handling.
 */

module tt_generic_wrapper (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    inout  wire [7:0] uio_inout,// Bidirectional input and output
    input  wire       clk,      // clock
    input  wire       rst_n     // reset - low to reset
);

    wire [7:0] uio_oe;
    wire [7:0] uio_in;
    wire [7:0] uio_out;

    // Instantiate the Tiny Tapeout project
    // ** Connect clk directly, remove clk2 **
    // ** Connect rst_n directly **
    tt_um_qspi_matrix_mult project (
        .ui_in(ui_in),		// 8-bit input
        .uo_out(uo_out),	// 8-bit output
        .uio_in(uio_in),	// 8-bit bidirectional (in)
        .uio_out(uio_out),	// 8-bit bidirectional (out)
        .uio_oe(uio_oe),	// 8-bit bidirectional (enable)
        .clk(clk),		    // Use the main clock
        .rst_n(rst_n)		// Pass reset directly
    );

    // Handle bidirectional I/Os
    generate
        genvar i;
        for (i = 0; i < 8; i = i + 1)
            assign uio_inout[i] = uio_oe[i] ? uio_out[i] : 1'bz;
    endgenerate
    assign uio_in = uio_inout;

    // ** Remove clock halving and reset inversion logic **

endmodule;