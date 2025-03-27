`default_nettype none

module top_arty_matrix_mult (
    input  wire       clk,      // 100MHz system clock
    input  wire       rst_n,    // Active-low reset (tied to push button)
    input  wire       uart_rx,  // UART receive from computer (FTDI chip)
    output wire       uart_tx   // UART transmit to computer (FTDI chip)
);

    // Internal connections between uart_to_qspi and matrix_mult
    wire [7:0] ui_in;           // Inputs to matrix multiplier
    wire [7:0] uo_out;          // Outputs from matrix multiplier
    wire [7:0] uio_inout;       // Bidirectional signals
    
    // Create separate QSPI wires for the two directions to avoid combinational loops
    wire [3:0] qspi_from_bridge_to_matrix;  // Data from UART bridge to matrix mult
    wire [3:0] qspi_from_matrix_to_bridge;  // Data from matrix mult to UART bridge
    
    // Control signals
    wire qspi_cs_n;             // Chip select
    wire qspi_clk;              // Clock
    wire [3:0] qspi_io_oe;      // Output enable
    
    // The UART-to-QSPI converter
    uart_to_qspi uart_qspi_bridge (
        .clk(clk),
        .resetn(rst_n),
        
        // UART connections to computer
        .ser_tx(uart_tx),
        .ser_rx(uart_rx),
        
        // QSPI connections to matrix multiplier
        .qspi_io_in(qspi_from_matrix_to_bridge),  // From matrix to bridge
        .qspi_io_out(qspi_from_bridge_to_matrix), // From bridge to matrix
        .qspi_csb(qspi_cs_n),                    // Chip select
        .qspi_sck(qspi_clk),                     // QSPI clock
        .qspi_io_oe(qspi_io_oe),                 // Output enable for QSPI
        
        // Unused management signals
        .mgmt_uart_rx(),
        .mgmt_uart_tx(1'b1),
        .mgmt_uart_enabled(1'b0)
    );
    
    // Connect QSPI signals to the matrix mult module's expected inputs/outputs
    assign ui_in[3:0] = qspi_from_bridge_to_matrix; // Connect bridge output to matrix input
    assign ui_in[4] = qspi_cs_n;                    // Chip select
    assign ui_in[5] = qspi_clk;                     // Clock
    assign ui_in[7:6] = 2'b00;                      // Unused inputs
    
    // Connect matrix multiplier output back to UART bridge input
    assign qspi_from_matrix_to_bridge = uo_out[3:0]; // Lower 4 bits from matrix to bridge
    
    // The matrix multiplication wrapper
    tt_generic_wrapper matrix_mult (
        .ui_in(ui_in),          // Input signals including QSPI control lines
        .uo_out(uo_out),        // Output signals including QSPI data out
        .uio_inout(uio_inout),  // Bidirectional signals
        .clk(clk),              // System clock
        .rst_n(rst_n)           // Reset
    );

endmodule