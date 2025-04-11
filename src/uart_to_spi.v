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
    
    // SPI bit rate divider (slower than UART to ensure stability)
    localparam SPI_DIV = 20;
    
    // States for state machines
    localparam IDLE         = 0;
    localparam UART_START   = 1;
    localparam UART_DATA    = 2;
    localparam UART_STOP    = 3;
    localparam SPI_START    = 4;
    localparam SPI_XFER     = 5;
    localparam SPI_END      = 6;
    localparam TX_START     = 7;
    localparam TX_DATA      = 8;
    localparam TX_STOP      = 9;
    localparam RESULT_READ  = 10;  // New state for reading results
    
    // State and counters
    reg [3:0] state;
    reg [15:0] clock_div;
    reg [2:0] bit_count;
    
    // Data registers
    reg [7:0] rx_data;      // Data received from UART
    reg [7:0] tx_data;      // Data to transmit via UART
    reg [7:0] spi_tx_data;  // Data to send via SPI
    reg [7:0] spi_rx_data;  // Data received from SPI
    
    // Result storage buffer
    reg [7:0] result_buf[0:3]; // Store 4 result bytes
    
    // Timeout counter for CS assertion
    reg [15:0] timeout_counter;
    
    // Matrix transaction phase tracking
    reg [2:0] byte_counter;    // Input matrix bytes (0-7)
    reg [1:0] result_counter;  // Output result bytes (0-3)
    reg results_pending;       // Flag indicating results are ready to be read
    reg input_complete;        // Flag indicating all input bytes are sent
    
    // Edge detection for UART RX
    reg ser_rx_prev;
    wire ser_rx_negedge = !ser_rx && ser_rx_prev;
    
    // Unused signals
    assign mgmt_uart_rx = ser_rx;
    
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= IDLE;
            clock_div <= 0;
            bit_count <= 0;
            rx_data <= 0;
            tx_data <= 0;
            spi_tx_data <= 0;
            spi_rx_data <= 0;
            spi_csb <= 1;
            spi_sck <= 0;
            spi_sdi <= 0;
            ser_tx <= 1;
            timeout_counter <= 0;
            byte_counter <= 0;
            result_counter <= 0;
            results_pending <= 0;
            input_complete <= 0;
            ser_rx_prev <= 1;
            
            // Clear result buffer
            result_buf[0] <= 0;
            result_buf[1] <= 0;
            result_buf[2] <= 0;
            result_buf[3] <= 0;
        end else begin
            // Update edge detector
            ser_rx_prev <= ser_rx;
            
            // Default decrements
            if (clock_div > 0) clock_div <= clock_div - 1;
            if (timeout_counter > 0) timeout_counter <= timeout_counter - 1;
            
            case (state)
                IDLE: begin
                    // Look for UART start bit
                    if (ser_rx_negedge) begin
                        clock_div <= UART_DIV / 2; // Sample in middle of bit
                        state <= UART_START;
                    end
                    
                    // Keep CS high when idle unless in the middle of transaction
                    if (timeout_counter == 0) begin
                        spi_csb <= 1;
                    end
                    
                    // If results are ready to send via UART
                    if (results_pending && result_counter < 4) begin
                        tx_data <= result_buf[result_counter];
                        state <= TX_START;
                    end
                end
                
                // UART Receive States
                UART_START: begin
                    if (clock_div == 0) begin
                        // Confirm this is a start bit
                        if (ser_rx == 0) begin
                            clock_div <= UART_DIV;
                            bit_count <= 0;
                            state <= UART_DATA;
                        end else begin
                            state <= IDLE;
                        end
                    end
                end
                
                UART_DATA: begin
                    if (clock_div == 0) begin
                        // Sample data bits (LSB first for UART)
                        rx_data <= {ser_rx, rx_data[7:1]};
                        bit_count <= bit_count + 1;
                        clock_div <= UART_DIV;
                        
                        if (bit_count == 7) begin
                            state <= UART_STOP;
                        end
                    end
                end
                
                UART_STOP: begin
                    if (clock_div == 0) begin
                        // Check for stop bit
                        if (ser_rx == 1) begin
                            // Valid byte received
                            spi_tx_data <= rx_data;
                            state <= SPI_START;
                            // Start/reset timeout for CS assertion
                            timeout_counter <= UART_DIV * 20;
                        end else begin
                            // Framing error, return to idle
                            state <= IDLE;
                        end
                    end
                end
                
                // SPI Transmit/Receive States
                SPI_START: begin
                    // Start SPI transaction
                    spi_csb <= 0;
                    spi_sck <= 0;
                    bit_count <= 0;
                    clock_div <= SPI_DIV;
                    state <= SPI_XFER;
                    spi_rx_data <= 0; // Clear receive buffer
                end
                
                SPI_XFER: begin
                    if (clock_div == 0) begin
                        if (!spi_sck) begin
                            // Prepare data bit (MSB first for SPI)
                            spi_sdi <= spi_tx_data[7];
                            spi_sck <= 1;
                            clock_div <= SPI_DIV;
                        end else begin
                            // Sample incoming data
                            spi_rx_data <= {spi_rx_data[6:0], spi_sdo};
                            spi_sck <= 0;
                            spi_tx_data <= {spi_tx_data[6:0], 1'b0};
                            bit_count <= bit_count + 1;
                            clock_div <= SPI_DIV;
                            
                            if (bit_count == 7) begin
                                state <= SPI_END;
                            end
                        end
                    end
                end
                
                SPI_END: begin
                    if (clock_div == 0) begin
                        if (!input_complete) begin
                            // Still sending input matrices
                            if (byte_counter < 7) begin
                                byte_counter <= byte_counter + 1;
                                state <= IDLE;
                            end else begin
                                // All matrix inputs sent, prepare to read results
                                byte_counter <= 0;
                                input_complete <= 1;
                                // De-assert CS to allow computation
                                spi_csb <= 1;
                                // Allow time for calculation
                                timeout_counter <= UART_DIV * 20;
                                state <= RESULT_READ;
                            end
                        end else begin
                            // Storing result bytes
                            if (byte_counter < 4) begin
                                result_buf[byte_counter] <= spi_rx_data;
                                byte_counter <= byte_counter + 1;
                                
                                if (byte_counter == 3) begin
                                    // All results collected
                                    results_pending <= 1;
                                    result_counter <= 0;
                                    state <= IDLE;
                                end else begin
                                    // Prepare for next result byte
                                    state <= SPI_START;
                                end
                            end
                        end
                    end
                end
                
                // Special state to start reading results
                RESULT_READ: begin
                    if (timeout_counter == 0) begin
                        // Start reading results
                        state <= SPI_START;
                        spi_csb <= 0;
                    end
                end
                
                // UART Transmit States
                TX_START: begin
                    // Start bit
                    ser_tx <= 0;
                    clock_div <= UART_DIV;
                    bit_count <= 0;
                    state <= TX_DATA;
                end
                
                TX_DATA: begin
                    if (clock_div == 0) begin
                        // Send data bits (LSB first)
                        ser_tx <= tx_data[bit_count];
                        bit_count <= bit_count + 1;
                        clock_div <= UART_DIV;
                        
                        if (bit_count == 7) begin
                            state <= TX_STOP;
                        end
                    end
                end
                
                TX_STOP: begin
                    if (clock_div == 0) begin
                        // Stop bit
                        ser_tx <= 1;
                        clock_div <= UART_DIV;
                        
                        // Increment result counter for next byte
                        result_counter <= result_counter + 1;
                        
                        if (result_counter == 3) begin
                            // All results sent, reset
                            results_pending <= 0;
                            input_complete <= 0;
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