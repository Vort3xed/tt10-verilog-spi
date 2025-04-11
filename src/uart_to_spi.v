`default_nettype none

module uart_to_spi (
    input  wire       clk,
    input  wire       resetn,
    
    // UART interface
    output reg        ser_tx,
    input  wire       ser_rx,
    
    // SPI interface
    input  wire       spi_sdo,  // MISO from slave
    output reg        spi_csb,  // CS to slave (active low)
    output reg        spi_sdi,  // MOSI to slave
    output reg        spi_sck,  // Clock to slave
    
    // Unused signals (kept for compatibility)
    output wire       mgmt_uart_rx,
    input  wire       mgmt_uart_tx,
    input  wire       mgmt_uart_enabled
);

    // UART baud rate divider (96 kbps @ 100 MHz clock)
    localparam UART_DIV = 1042;
    
    // SPI bit rate divider (slower than UART for stability)
    localparam SPI_DIV = 40;
    
    // UART RX/TX modes
    localparam DATA_BITS = 8;
    localparam LSB_FIRST = 1;
    
    // States for the main state machine
    localparam IDLE             = 0;
    localparam RX_START_BIT     = 1;
    localparam RX_DATA_BITS     = 2;
    localparam RX_STOP_BIT      = 3;
    localparam TX_START_BIT     = 4;
    localparam TX_DATA_BITS     = 5;
    localparam TX_STOP_BIT      = 6;
    localparam SPI_START        = 7;
    localparam SPI_TX_BIT       = 8;
    localparam SPI_RX_BIT       = 9;
    localparam SPI_WAIT_FOR_RESULTS = 10;
    
    // Main state and counters
    reg [3:0] state = IDLE;
    reg [15:0] divider_counter = 0;
    reg [3:0] bit_counter = 0;
    reg [3:0] byte_counter = 0;
    
    // Data buffers
    reg [7:0] uart_rx_data;
    reg [7:0] uart_tx_data;
    reg [7:0] spi_tx_data;
    reg [7:0] spi_rx_data;
    
    // Matrix data storage
    reg [7:0] matrix_A[0:3];
    reg [7:0] matrix_B[0:3];
    reg [7:0] results[0:3];
    
    // Control flags
    reg all_data_received = 0;    // Set when all input matrices received
    reg compute_done = 0;         // Set when computation is complete
    reg results_ready = 0;        // Set when results are available
    reg wait_for_response = 0;    // Set when waiting for matrix module response
    
    // Edge detection for UART RX
    reg uart_rx_prev;
    wire uart_rx_negedge = uart_rx_prev && !uart_rx;
    
    // Unused outputs
    assign mgmt_uart_rx = 1'b0;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            // Reset all states and signals
            state <= IDLE;
            divider_counter <= 0;
            bit_counter <= 0;
            byte_counter <= 0;
            
            uart_rx_data <= 0;
            uart_tx_data <= 0;
            spi_tx_data <= 0;
            spi_rx_data <= 0;
            
            spi_csb <= 1;  // Deselect chip
            spi_sck <= 0;  // Clock low
            spi_sdi <= 0;  // Data line low
            ser_tx <= 1;   // UART idle high
            
            uart_rx_prev <= 1;
            
            all_data_received <= 0;
            compute_done <= 0;
            results_ready <= 0;
            wait_for_response <= 0;
        end else begin
            // Update edge detector
            uart_rx_prev <= uart_rx;
            
            // Default decrement for counter
            if (divider_counter > 0) begin
                divider_counter <= divider_counter - 1;
            end
            
            case (state)
                IDLE: begin
                    // Default inactive states
                    spi_sck <= 0;
                    
                    if (!all_data_received && uart_rx_negedge) begin
                        // Start receiving UART byte
                        state <= RX_START_BIT;
                        divider_counter <= UART_DIV / 2;  // Sample middle of bit
                    end
                    else if (all_data_received && !compute_done) begin
                        // After all data is received, trigger SPI transaction
                        state <= SPI_START;
                        byte_counter <= 0;  // Start with first matrix element
                    end
                    else if (compute_done && !results_ready) begin
                        // After computation, read results
                        state <= SPI_START;
                        byte_counter <= 0;  // Reset counter for reading results
                        wait_for_response <= 1;
                    end
                    else if (results_ready) begin
                        // Send results back over UART
                        uart_tx_data <= results[byte_counter];
                        state <= TX_START_BIT;
                    end
                end
                
                //------------------------------------------
                // UART Receive States
                //------------------------------------------
                RX_START_BIT: begin
                    if (divider_counter == 0) begin
                        // Verify this is a valid start bit
                        if (uart_rx == 0) begin
                            divider_counter <= UART_DIV;
                            bit_counter <= 0;
                            state <= RX_DATA_BITS;
                            uart_rx_data <= 0;  // Clear data register
                        end else begin
                            state <= IDLE;  // Not a valid start bit
                        end
                    end
                end
                
                RX_DATA_BITS: begin
                    if (divider_counter == 0) begin
                        // Sample data bit
                        if (LSB_FIRST) begin
                            uart_rx_data <= {uart_rx, uart_rx_data[7:1]};  // LSB first
                        end else begin
                            uart_rx_data <= {uart_rx_data[6:0], uart_rx};  // MSB first
                        end
                        
                        bit_counter <= bit_counter + 1;
                        divider_counter <= UART_DIV;
                        
                        if (bit_counter == DATA_BITS-1) begin
                            state <= RX_STOP_BIT;
                        end
                    end
                end
                
                RX_STOP_BIT: begin
                    if (divider_counter == 0) begin
                        // Check stop bit
                        if (uart_rx == 1) begin
                            // Store received data
                            if (byte_counter < 4) begin
                                // Matrix A data
                                matrix_A[byte_counter] <= uart_rx_data;
                            end else if (byte_counter < 8) begin
                                // Matrix B data
                                matrix_B[byte_counter-4] <= uart_rx_data;
                            end
                            
                            byte_counter <= byte_counter + 1;
                            
                            if (byte_counter == 7) begin
                                // All matrix data received
                                all_data_received <= 1;
                            end
                            
                            state <= IDLE;
                        end else begin
                            state <= IDLE;  // Framing error, discard
                        end
                    end
                end
                
                //------------------------------------------
                // SPI Data Transfer States
                //------------------------------------------
                SPI_START: begin
                    // Start SPI transaction
                    spi_csb <= 0;  // Select device
                    spi_sck <= 0;  // Clock low
                    
                    // Select data to send based on state
                    if (!compute_done) begin
                        // Send input matrices
                        if (byte_counter < 4) begin
                            spi_tx_data <= matrix_A[byte_counter];
                        end else begin
                            spi_tx_data <= matrix_B[byte_counter-4];
                        end
                    end
                    
                    bit_counter <= 0;
                    divider_counter <= SPI_DIV;
                    state <= SPI_TX_BIT;
                    spi_rx_data <= 0;  // Clear receive register
                end
                
                SPI_TX_BIT: begin
                    if (divider_counter == 0) begin
                        // Setup MSB first on MOSI
                        spi_sdi <= spi_tx_data[7 - bit_counter];
                        spi_sck <= 1;  // Clock high to sample
                        divider_counter <= SPI_DIV;
                        state <= SPI_RX_BIT;
                    end
                end
                
                SPI_RX_BIT: begin
                    if (divider_counter == 0) begin
                        // Sample MISO on clock high
                        if (wait_for_response) begin
                            // Shift in MISO data MSB first
                            spi_rx_data <= {spi_rx_data[6:0], spi_sdo};
                        end
                        
                        spi_sck <= 0;  // Clock low
                        divider_counter <= SPI_DIV;
                        bit_counter <= bit_counter + 1;
                        
                        if (bit_counter == 7) begin
                            // Byte complete
                            if (!compute_done) begin
                                // Sending matrix data
                                if (byte_counter < 7) begin
                                    byte_counter <= byte_counter + 1;
                                    state <= SPI_START;  // Send next byte
                                end else begin
                                    // All data sent, wait for computation
                                    spi_csb <= 0; // Keep CS low for reading
                                    divider_counter <= UART_DIV * 10;  // Wait time
                                    state <= SPI_WAIT_FOR_RESULTS;
                                    compute_done <= 1;
                                }
                            end else if (wait_for_response) begin
                                // Reading results
                                results[byte_counter] <= spi_rx_data;
                                
                                if (byte_counter < 3) begin
                                    byte_counter <= byte_counter + 1;
                                    state <= SPI_START;  // Read next result
                                end else begin
                                    // All results read
                                    spi_csb <= 1;  // Deselect chip
                                    byte_counter <= 0;  // Reset for UART TX
                                    results_ready <= 1;
                                    wait_for_response <= 0;
                                    state <= IDLE;
                                }
                            end
                        end else begin
                            // Continue with next bit
                            state <= SPI_TX_BIT;
                        end
                    end
                end
                
                SPI_WAIT_FOR_RESULTS: begin
                    if (divider_counter == 0) begin
                        // Computation time complete
                        wait_for_response <= 1;
                        state <= IDLE;  // Will trigger result reading
                    end
                end
                
                //------------------------------------------
                // UART Transmit States
                //------------------------------------------
                TX_START_BIT: begin
                    // Send start bit (low)
                    ser_tx <= 0;
                    divider_counter <= UART_DIV;
                    bit_counter <= 0;
                    state <= TX_DATA_BITS;
                end
                
                TX_DATA_BITS: begin
                    if (divider_counter == 0) begin
                        // Send data bits
                        if (LSB_FIRST) begin
                            ser_tx <= (uart_tx_data >> bit_counter) & 1;  // LSB first
                        end else begin
                            ser_tx <= (uart_tx_data >> (7 - bit_counter)) & 1;  // MSB first
                        end
                        
                        bit_counter <= bit_counter + 1;
                        divider_counter <= UART_DIV;
                        
                        if (bit_counter == DATA_BITS-1) begin
                            state <= TX_STOP_BIT;
                        end
                    end
                end
                
                TX_STOP_BIT: begin
                    if (divider_counter == 0) begin
                        // Send stop bit (high)
                        ser_tx <= 1;
                        divider_counter <= UART_DIV;
                        
                        byte_counter <= byte_counter + 1;
                        
                        if (byte_counter == 3) begin
                            // All results sent, reset for next transaction
                            all_data_received <= 0;
                            compute_done <= 0;
                            results_ready <= 0;
                            wait_for_response <= 0;
                            byte_counter <= 0;
                        end
                        
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire