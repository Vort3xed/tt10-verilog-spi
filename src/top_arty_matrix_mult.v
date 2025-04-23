`default_nettype none

module top_arty_matrix_mult (
    input  wire       clk,      // 100MHz system clock
    input  wire       rst_n,    // Active-low reset (tied to push button)
    input  wire       uart_rx,  // UART receive from computer (FTDI chip)
    output wire       uart_tx   // UART transmit to computer (FTDI chip)
);

    // Internal connections to matrix_mult
    wire [7:0] ui_in;
    wire [7:0] uo_out;
    wire [7:0] uio_inout;
    
    // Connect UART directly to the matrix multiplier
    assign ui_in = {7'b0000000, uart_rx};  // Connect UART RX to ui_in[0]
    assign uart_tx = uo_out[0];            // Connect UART TX from uo_out[0]
    
    // The matrix multiplication wrapper
    tt_generic_wrapper matrix_mult (
        .ui_in(ui_in),          // Input signals including UART RX
        .uo_out(uo_out),        // Output signals including UART TX
        .uio_inout(uio_inout),  // Bidirectional signals (unused)
        .clk(clk),              // System clock
        .rst_n(rst_n)           // Reset
    );

endmodule