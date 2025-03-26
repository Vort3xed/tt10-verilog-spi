`default_nettype none

module top_arty_matrix_mult (
    input  wire       clk,      // 100MHz system clock
    input  wire       rst_n,    // Active-low reset (tied to push button)
    input  wire       uart_rx,  // UART receive from computer (FTDI chip)
    output wire       uart_tx   // UART transmit to computer (FTDI chip)
);

    // Internal connections between uart_to_spi and matrix_mult
    wire [7:0] ui_in;
    wire [7:0] uo_out;
    wire [7:0] uio_inout;
    
    // The UART-to-SPI converter
    uart_to_spi uart_spi_bridge (
        .clk(clk),
        .resetn(rst_n),
        
        // UART connections to computer
        .ser_tx(uart_tx),
        .ser_rx(uart_rx),
        
        // SPI connections to matrix multiplier
        .spi_csb(ui_in[4]),         // Chip select
        .spi_sck(ui_in[5]),         // SPI clock - FIXED: was spi_clk
        .spi_sdi(ui_in[0]),         // SPI data in (only using one bit since standard SPI)
        .spi_sdo(uo_out[0]),        // SPI data out (only using one bit since standard SPI)
        
        // Unused signals
        .mgmt_uart_rx(),
        .mgmt_uart_tx(1'b1),
        .mgmt_uart_enabled(1'b0)
    );
    
    // Extend the single SPI data line to all 4 QSPI lines for data input
    assign ui_in[3:1] = {3{ui_in[0]}};
    
    // The matrix multiplication wrapper
    tt_generic_wrapper matrix_mult (
        .ui_in(ui_in),          // Input signals including SPI control lines
        .uo_out(uo_out),        // Output signals including SPI data out
        .uio_inout(uio_inout),  // Bidirectional signals
        .clk(clk),              // System clock
        .rst_n(rst_n)           // Reset
    );

endmodule