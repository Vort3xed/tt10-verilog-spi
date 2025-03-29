`default_nettype none

module uart_to_qspi (
    input wire clk,
    input wire resetn,
    // UART interface
    output wire ser_tx,
    input wire ser_rx,
    // QSPI interface
    input wire [3:0] qspi_io_in,    // 4-bit input for QSPI
    output reg [3:0] qspi_io_out,   // 4-bit output for QSPI  
    output reg qspi_csb,            // Chip select
    output reg qspi_sck,            // Clock
    output reg [3:0] qspi_io_oe,    // Output enable
    // Management UART
    output wire mgmt_uart_rx,
    input wire mgmt_uart_tx,
    input wire mgmt_uart_enabled
);
    wire [15:0] cfg_divider;        // Fixed divider
    assign cfg_divider = 16'd1042;  // For 96kbps baud rate

    //============ UART Receiver Section ============//
    reg [3:0] recv_state;
    reg [15:0] recv_divcnt;
    reg [7:0] recv_pattern;
    reg [7:0] recv_buf_data;
    reg recv_buf_valid;

    always @(posedge clk) begin
        if (!resetn) begin
            recv_state <= 0;
            recv_divcnt <= 0;
            recv_pattern <= 0;
            recv_buf_data <= 0;
            recv_buf_valid <= 0;
        end else begin
            recv_divcnt <= recv_divcnt + 1;
            case (recv_state)
                0: begin
                    if (!ser_rx) begin
                        recv_state <= 1;
                    end
                    recv_divcnt <= 0;
                    recv_buf_valid <= 0;
                end
                1: begin
                    // Wait for 1/2 expected bit period to sample in the middle
                    if (2*recv_divcnt > cfg_divider) begin
                        recv_state <= 2;
                        recv_divcnt <= 0;
                    end
                end
                10: begin
                    if (recv_divcnt > cfg_divider) begin
                        recv_buf_data <= recv_pattern;
                        recv_buf_valid <= 1;
                        recv_state <= 11;
                        recv_divcnt <= 0;
                    end
                end
                11: begin
                    recv_divcnt <= 0;
                    recv_state <= 0;
                end
                default: begin
                    if (recv_divcnt > cfg_divider) begin
                        // UART uses LSB first
                        recv_pattern <= {ser_rx, recv_pattern[7:1]};
                        recv_state <= recv_state + 1;
                        recv_divcnt <= 0;
                    end
                end
            endcase
        end
    end

    // UART output mux with Caravel's UART
    assign ser_tx = mgmt_uart_enabled ? (mgmt_uart_tx & retn_pattern[0]) : retn_pattern[0];
    
    // Copy UART input to management UART
    assign mgmt_uart_rx = ser_rx;

    //============ QSPI Communication Section ============//
    reg [2:0] send_state;
    reg [2:0] send_byte_cnt;   // Count whole bytes
    reg [1:0] send_nibble_cnt; // Count nibbles within a byte
    reg [15:0] send_divcnt;
    reg [7:0] send_buf_data;   // Current byte being processed
    reg [7:0] recv_qspi_data;  // Data received from QSPI
    
    // QSPI return data communication
    reg [7:0] retn_buf_data;   // Return data from QSPI
    reg retn_active;
    reg [1:0] retn_state;
    reg [9:0] retn_pattern;
    reg [3:0] retn_bitcnt;
    reg [15:0] retn_divcnt;

    reg [3:0] transaction_counter;
    reg result_phase;
    reg [3:0] result_counter;  // Add counter for result bytes
    reg result_nibble_flag;

    always @(posedge clk) begin
        if (!resetn) begin
            send_divcnt <= 0;
            send_state <= 0;
            send_byte_cnt <= 0;
            send_nibble_cnt <= 0;
            send_buf_data <= 0;
            recv_qspi_data <= 0;
            qspi_csb <= 1;
            qspi_sck <= 0;
            qspi_io_out <= 4'b0000;
            qspi_io_oe <= 4'b0000;
            retn_active <= 0;

            transaction_counter <= 0;
            result_phase <= 0;
            result_counter <= 0;
            result_nibble_flag <= 0;
        end else begin
            case (send_state)
                0: begin
                    // Idle state - wait for data from UART
                    if (recv_buf_valid == 1) begin
                        // Assert CS for a new transaction or during result phase
                        if (transaction_counter == 0 || result_phase) begin
                            qspi_csb <= 0;  // Assert chip select
                        end
                        send_state <= 1;
                        send_byte_cnt <= 0;
                        send_nibble_cnt <= 0;
                        send_buf_data <= recv_buf_data;
                        send_divcnt <= 0;
                        qspi_io_oe <= 4'b1111;  // Output enabled for sending
                    end else if (recv_state != 0) begin
                        send_divcnt <= 0;
                    // Only reset on very long timeout, not between each byte
                    end else if (send_divcnt > 100*cfg_divider) begin
                        // Only long timeout resets everything
                        qspi_csb <= 1;
                        qspi_io_oe <= 4'b0000;
                        transaction_counter <= 0;
                    end else begin
                        send_divcnt <= send_divcnt + 1;
                    end
                end
                
                1: begin
                    // Prepare to send first nibble (high 4 bits)
                    qspi_sck <= 0;
                    qspi_io_out <= send_buf_data[7:4];  // Send high nibble
                    send_divcnt <= 0;
                    send_state <= 2;
                end
                
                2: begin
                    // Wait for half clock period
                    send_divcnt <= send_divcnt + 1;
                    if (2*send_divcnt > cfg_divider) begin
                        qspi_sck <= 1;  // Clock high - target will read data
                        send_divcnt <= 0;
                        send_state <= 3;
                    end
                end
                
                3: begin
                    // Capture returned data on clock high
                    // Wait for half clock period
                    send_divcnt <= send_divcnt + 1;
                    if (2*send_divcnt > cfg_divider) begin
                        qspi_sck <= 0;  // Clock low
                        
                        // Capture data from QSPI (if applicable)
                        if (send_nibble_cnt == 0) begin
                            // Store high nibble
                            recv_qspi_data[7:4] <= qspi_io_in;
                            send_nibble_cnt <= 1;
                            // Prepare low nibble
                            qspi_io_out <= send_buf_data[3:0];
                            send_state <= 2;  // Go back to clock high state
                        end else begin
                            // Store low nibble
                            recv_qspi_data[3:0] <= qspi_io_in;
                            send_nibble_cnt <= 0;
                            
                            // Move to next byte or finish
                            if (send_byte_cnt < 7) begin  // Maximum 8 bytes (0-7)
                                send_byte_cnt <= send_byte_cnt + 1;
                                retn_buf_data <= recv_qspi_data;  // Save for return
                                retn_active <= 1;  // Trigger UART return
                                
                                // Check if there's more data from UART
                                if (recv_buf_valid) begin
                                    send_buf_data <= recv_buf_data;
                                    send_state <= 1;  // Start next byte
                                end else begin
                                    send_state <= 4;  // Done
                                end
                            end else begin
                                send_state <= 4;
                            end
                        end
                        
                        send_divcnt <= 0;
                    end
                end
                
                4: begin
                    // Transmission complete for this byte
                    transaction_counter <= transaction_counter + 1;
                    
                    // Enter result phase after all 8 bytes are sent
                    if (transaction_counter >= 7) begin
                        result_phase <= 1;  // Start result phase
                        
                        // DO NOT DEASSERT CS YET - we need it for results
                        // qspi_csb <= 1;  // Comment out this line
                        
                        // We should also start generating clock pulses to receive results
                        send_state <= 5;  // Go to result reading state
                    end else begin
                        send_state <= 0;  // Return to idle for next byte
                    end
                    
                    qspi_io_oe <= 4'b0000;  // Disable output
                    retn_buf_data <= recv_qspi_data;  // Save last byte
                    retn_active <= 1;  // Trigger UART return
                end
                
                5: begin
                    // In this state, we generate clock pulses and read back the 4 result bytes
                    
                    // Keep OE disabled during reading
                    qspi_io_oe <= 4'b0000;
                    
                    // Generate clock pulses and read data
                    send_divcnt <= send_divcnt + 1;
                    if (send_divcnt > cfg_divider) begin
                        // Toggle clock
                        qspi_sck <= ~qspi_sck;
                        send_divcnt <= 0;
                        
                        // On rising edge, capture data
                        if (~qspi_sck) begin  // About to rise
                            // We'll process the data on the next falling edge
                        end else begin  // Just rose, will fall next
                            // On falling edge, process the captured data
                            if (!result_nibble_flag) begin
                                // Store high nibble
                                recv_qspi_data[7:4] <= qspi_io_in;
                                result_nibble_flag <= 1;
                                $display("RESULT: Received high nibble %h for result %d", qspi_io_in, result_counter);
                            end else begin
                                // Store low nibble and complete byte
                                recv_qspi_data[3:0] <= qspi_io_in;
                                result_nibble_flag <= 0;
                                $display("RESULT: Received complete result byte %h for position %d", 
                                        {recv_qspi_data[7:4], qspi_io_in}, result_counter);
                                
                                // Send back the completed byte via UART
                                retn_buf_data <= {recv_qspi_data[7:4], qspi_io_in};
                                retn_active <= 1;
                                
                                // Move to next result or finish
                                result_counter <= result_counter + 1;
                                if (result_counter >= 3) begin
                                    // Wait until UART transmission is complete before ending
                                    if (retn_state == 0 && !retn_active) begin
                                        // All 4 results received and transmitted
                                        send_state <= 0;  // Return to idle
                                        qspi_csb <= 1;    // Deassert chip select
                                        result_phase <= 0; // End result phase
                                        $display("RESULT: All 4 result bytes received and transmitted, ending transaction");
                                    end
                                end
                            end
                        end
                    end
                end
            endcase
        end
    end

    //============ UART Return Data Section ============//
    // ... in the UART Return Data Section ... 
    always @(posedge clk) begin
        if (!resetn) begin
            retn_pattern <= ~0;
            retn_bitcnt <= 0;
            retn_divcnt <= 0;
            retn_state <= 0;
            retn_active <= 0;
        end else begin
            retn_divcnt <= retn_divcnt + 1;
            
            case (retn_state)
                0: begin
                    if (retn_active == 1) begin
                        retn_pattern <= {1'b1, retn_buf_data, 1'b0};  // UART framing
                        retn_bitcnt <= 10;
                        retn_divcnt <= 0;
                        retn_state <= 1;
                        retn_active <= 0;
                    end
                end
                1: begin
                    if (retn_divcnt > cfg_divider && retn_bitcnt) begin
                        retn_pattern <= {1'b1, retn_pattern[9:1]};
                        retn_bitcnt <= retn_bitcnt - 1;
                        retn_divcnt <= 0;
                    end else if (!retn_bitcnt) begin
                        retn_state <= 0;
                    end
                end
            endcase
        end
    end

endmodule
`default_nettype wire