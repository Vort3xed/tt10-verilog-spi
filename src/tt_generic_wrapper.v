/*
 * tt_um_rte_sine_synth_wrapper.v
 *
 * Wrapper for Arty A7 board around the
 * TinyTapeout project tt_um_rte_sine_synth.v
 *
 * What this wrapper adds:
 *
 * (1) Divide-by-2 on the clock to match the TinyTapeout
 *     development board running at 50MHz
 * (2) Bidirectional pin handling
 *
 */

// Point this to the Tiny Tapeout project and uncomment
// `include "../src/tt_um_project.v"

// Note that this creates new signal name "uio_inout" which is
// what must be connected to the eight pins in the "JB" PMOD
// in the Arty board configuration file.

module tt_generic_wrapper (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    inout  wire [7:0] uio_inout,// Bidirectional input and output
    input  wire       clk,      // clock
    input  wire       rst_n     // reset - low to reset
);

    reg clk2;

    wire [7:0] uio_oe;
    wire [7:0] uio_in;
    wire [7:0] uio_out;

    // Instantiate the Tiny Tapeout project (using standard SPI version)

    tt_um_spi_matrix_mult project (
	.ui_in(ui_in),		// 8-bit input (contains SPI signals)
	.uo_out(uo_out),	// 8-bit output (contains SPI SDO)
	.uio_in(uio_in),	// 8-bit bidirectional (in) - Unused by SPI project
	.uio_out(uio_out),	// 8-bit bidirectional (out) - Unused by SPI project
	.uio_oe(uio_oe),	// 8-bit bidirectional (enable) - Unused by SPI project
	.clk(clk2),		    // halved clock (system clock for the project)
	.rst_n(rst_n)		// active low reset
    );

    // Handle bidirectional I/Os
    generate
        genvar i;
        for (i = 0; i < 8; i = i + 1)
            assign uio_inout[i] = uio_oe[i] ? uio_out[i] : 1'bz;
    endgenerate
    assign uio_in = uio_inout;

    // Invert reset to project, and halve the clock

    always @(posedge clk) begin
	if (rst_n) begin
	    clk2 <= ~clk2;
	end else begin
	    clk2 <= 0;
	end
    end

endmodule;
