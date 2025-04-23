/*
 * tt_generic_wrapper.v
 *
 * Wrapper for Arty A7 board around the
 * TinyTapeout project tt_um_uart_matrix_mult
 *
 * What this wrapper adds:
 *
 * (1) Divide-by-2 on the clock to match the TinyTapeout
 *     development board running at 50MHz
 *
 */

module tt_generic_wrapper (
    input  wire [7:0] ui_in,    // Dedicated inputs - ui_in[0] is UART RX
    output wire [7:0] uo_out,   // Dedicated outputs - uo_out[0] is UART TX
    inout  wire [7:0] uio_inout,// Bidirectional input and output (unused)
    input  wire       clk,      // clock
    input  wire       rst_n     // reset - low to reset
);

    reg clk2;

    wire [7:0] uio_oe;
    wire [7:0] uio_in;
    wire [7:0] uio_out;

    // Instantiate the Tiny Tapeout project
    tt_um_uart_matrix_mult project (
    .ui_in(ui_in),		// 8-bit input - ui_in[0] is UART RX
    .uo_out(uo_out),	// 8-bit output - uo_out[0] is UART TX
    .uio_in(uio_in),	// 8-bit bidirectional (in)
    .uio_out(uio_out),	// 8-bit bidirectional (out)
    .uio_oe(uio_oe),	// 8-bit bidirectional (enable)
    .clk(clk2),		    // halved clock
    .rst_n(rst_n),		// inverted reset
    .ena(1'b1)          // always enabled
    );

    // Handle bidirectional I/Os
    generate
        genvar i;
        for (i = 0; i < 8; i = i + 1)
            assign uio_inout[i] = uio_oe[i] ? uio_out[i] : 1'bz;
    endgenerate
    assign uio_in = uio_inout;

    // Divide clock by 2 to get 50MHz from 100MHz input
    always @(posedge clk) begin
    if (rst_n) begin
        clk2 <= ~clk2;
    end else begin
        clk2 <= 0;
    end
    end

endmodule