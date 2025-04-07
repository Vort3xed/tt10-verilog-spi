`default_nettype none

module top_arty_matrix_mult (
    input  wire       clk,      // 100MHz system clock
    input  wire       rst_n,    // Active-low reset (tied to push button)
    input  wire       uart_rx,  // UART receive from computer (FTDI chip)
    output wire       uart_tx   // UART transmit to computer (FTDI chip)
);

    // Internal SPI connections between uart_to_spi and matrix_mult wrapper
    wire spi_csb; // Chip Select Bar (Active Low)
    wire spi_sck; // SPI Clock
    wire spi_sdi; // SPI Data In (Master Out -> Slave In)
    wire spi_sdo; // SPI Data Out (Master In <- Slave Out)

    // Map SPI signals to the wrapper's ui_in/uo_out buses
    // Wrapper expects: ui_in[0]=SDI, ui_in[4]=CS_N, ui_in[5]=SCK
    // Wrapper provides: uo_out[0]=SDO
    wire [7:0] wrapper_ui_in = {2'b00, spi_sck, spi_csb, 3'b000, spi_sdi};
    wire [7:0] wrapper_uo_out;
    assign spi_sdo = wrapper_uo_out[0];

    // Unused bidirectional signals for the wrapper
    wire [7:0] wrapper_uio_inout; // Tied to high-Z below

    // The UART-to-SPI converter
    uart_to_spi uart_spi_bridge (
        .clk(clk),                  // System clock (100MHz)
        .resetn(rst_n),             // System reset

        // UART connections to computer
        .ser_tx(uart_tx),
        .ser_rx(uart_rx),

        // SPI Master connections (to matrix multiplier slave)
        .spi_csb(spi_csb),          // Chip select output
        .spi_sck(spi_sck),          // SPI clock output
        .spi_sdi(spi_sdi),          // SPI data output (MOSI)
        .spi_sdo(spi_sdo),          // SPI data input (MISO)

        // Unused management UART signals
        .mgmt_uart_rx(),            // Tie off input
        .mgmt_uart_tx(1'b1),        // Tie off output
        .mgmt_uart_enabled(1'b0)    // Disable management UART
    );

    // The matrix multiplication wrapper (containing the standard SPI project)
    tt_generic_wrapper matrix_mult (
        .ui_in(wrapper_ui_in),      // Input signals including SPI
        .uo_out(wrapper_uo_out),    // Output signals including SPI SDO
        .uio_inout(wrapper_uio_inout), // Bidirectional signals (unused by SPI core)
        .clk(clk),                  // System clock (gets halved inside wrapper)
        .rst_n(rst_n)               // System reset
    );

    // Ensure unused bidirectional pins are high-Z
    assign wrapper_uio_inout = 8'hZZ;

endmodule
`default_nettype wire // Added this line as it was missing
