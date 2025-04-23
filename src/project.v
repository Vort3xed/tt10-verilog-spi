/*
 * Copyright (c) 2024 Agneya Tharun 
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_uart_matrix_mult (
    input  wire [7:0] ui_in,    // [0] = uart_rx
    output wire [7:0] uo_out,   // [0] = uart_tx
    input  wire [7:0] uio_in,   
    output wire [7:0] uio_out,  
    output wire [7:0] uio_oe,   
    input  wire       ena,      // Always 1 when design is powered
    input  wire       clk,      // System clock
    input  wire       rst_n     // Active-low reset
);

  // UART signals
  wire uart_rx = ui_in[0];
  reg uart_tx;
  assign uo_out = {7'b0000000, uart_tx};
  
  // We're not using bidirectional pins in this design
  assign uio_out = 8'b00000000;
  assign uio_oe = 8'b00000000;
  
  // UART parameters (assuming 9600 baud with 50MHz clock)
  localparam CLK_FREQ = 50_000_000;
  localparam BAUD_RATE = 9600;
  localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE;
  
  // UART state machine definitions
  localparam UART_IDLE = 0,
             UART_START = 1,
             UART_DATA = 2,
             UART_STOP = 3;

  // Matrix multiplication state machine
  localparam STATE_IDLE = 0,
             STATE_READ_A = 1,
             STATE_READ_B = 2,
             STATE_COMPUTE = 3,
             STATE_OUTPUT = 4;
  
  // Registers for UART receiver
  reg [2:0] rx_state;
  reg [15:0] rx_counter;
  reg [2:0] rx_bit_index;
  reg [7:0] rx_data;
  
  // Registers for UART transmitter
  reg [2:0] tx_state;
  reg [15:0] tx_counter;
  reg [2:0] tx_bit_index;
  reg [7:0] tx_data;
  reg tx_busy;

  // Registers for state machine and data
  reg [2:0] state;
  reg [2:0] counter;
  
  // Matrix storage (8-bit values)
  reg [7:0] A0, A1, A2, A3;   // Elements for matrix A
  reg [7:0] B0, B1, B2, B3;   // Elements for matrix B
  reg [15:0] C00, C01, C10, C11; // Full-precision intermediate products
  
  // Buffer for output data
  reg [7:0] output_buffer[0:3];
  reg [1:0] output_index;
  reg data_ready;
  
  // UART Receiver logic
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_state <= UART_IDLE;
      rx_counter <= 0;
      rx_bit_index <= 0;
      rx_data <= 0;
      data_ready <= 0;
    end else begin
      case (rx_state)
        UART_IDLE: begin
          rx_counter <= 0;
          rx_bit_index <= 0;
          if (uart_rx == 0) begin  // Start bit detected
            rx_state <= UART_START;
          end
        end
        
        UART_START: begin
          if (rx_counter == BIT_PERIOD/2) begin  // Sample in middle of start bit
            if (uart_rx == 0) begin  // Confirm start bit
              rx_state <= UART_DATA;
              rx_counter <= 0;
            end else begin
              rx_state <= UART_IDLE;  // False start
            end
          end else begin
            rx_counter <= rx_counter + 1;
          end
        end
        
        UART_DATA: begin
          if (rx_counter == BIT_PERIOD) begin  // Sample in middle of data bit
            rx_data <= {uart_rx, rx_data[7:1]};  // LSB first
            rx_counter <= 0;
            if (rx_bit_index == 7) begin  // Received all 8 bits
              rx_state <= UART_STOP;
            end else begin
              rx_bit_index <= rx_bit_index + 1;
            end
          end else begin
            rx_counter <= rx_counter + 1;
          end
        end
        
        UART_STOP: begin
          if (rx_counter == BIT_PERIOD) begin  // End of stop bit
            rx_state <= UART_IDLE;
            rx_counter <= 0;
            data_ready <= 1;  // Signal data is ready
          end else begin
            rx_counter <= rx_counter + 1;
          end
        end
      endcase
    end
  end

  // UART Transmitter logic
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      uart_tx <= 1;  // Idle state is high
      tx_state <= UART_IDLE;
      tx_counter <= 0;
      tx_bit_index <= 0;
      tx_busy <= 0;
    end else begin
      case (tx_state)
        UART_IDLE: begin
          uart_tx <= 1;  // Idle state is high
          tx_counter <= 0;
          tx_bit_index <= 0;
          if (state == STATE_OUTPUT && !tx_busy && output_index < 4) begin
            tx_data <= output_buffer[output_index];
            tx_busy <= 1;
            tx_state <= UART_START;
          end
        end
        
        UART_START: begin
          uart_tx <= 0;  // Start bit is low
          if (tx_counter == BIT_PERIOD - 1) begin
            tx_counter <= 0;
            tx_state <= UART_DATA;
          end else begin
            tx_counter <= tx_counter + 1;
          end
        end
        
        UART_DATA: begin
          uart_tx <= tx_data[tx_bit_index];  // LSB first
          if (tx_counter == BIT_PERIOD - 1) begin
            tx_counter <= 0;
            if (tx_bit_index == 7) begin  // Sent all 8 bits
              tx_state <= UART_STOP;
            end else begin
              tx_bit_index <= tx_bit_index + 1;
            end
          end else begin
            tx_counter <= tx_counter + 1;
          end
        end
        
        UART_STOP: begin
          uart_tx <= 1;  // Stop bit is high
          if (tx_counter == BIT_PERIOD - 1) begin
            tx_counter <= 0;
            tx_state <= UART_IDLE;
            tx_busy <= 0;
            output_index <= output_index + 1;
          end else begin
            tx_counter <= tx_counter + 1;
          end
        end
      endcase
    end
  end
  
  // Main state machine for matrix multiplication
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= STATE_IDLE;
      counter <= 0;
      A0 <= 0; A1 <= 0; A2 <= 0; A3 <= 0;
      B0 <= 0; B1 <= 0; B2 <= 0; B3 <= 0;
      C00 <= 0; C01 <= 0; C10 <= 0; C11 <= 0;
      output_index <= 0;
    end else begin
      // Handle the received data
      if (data_ready) begin
        case (state)
          STATE_IDLE: begin
            state <= STATE_READ_A;
            counter <= 0;
          end
          
          STATE_READ_A: begin
            case (counter)
              0: A0 <= rx_data;
              1: A1 <= rx_data;
              2: A2 <= rx_data;
              3: begin
                 A3 <= rx_data;
                 state <= STATE_READ_B;
                 counter <= 0;
                end
              default: counter <= 0;
            endcase
            if (state == STATE_READ_A) counter <= counter + 1;
          end
          
          STATE_READ_B: begin
            case (counter)
              0: B0 <= rx_data;
              1: B1 <= rx_data;
              2: B2 <= rx_data;
              3: begin
                 B3 <= rx_data;
                 state <= STATE_COMPUTE;
                 counter <= 0;
                end
              default: counter <= 0;
            endcase
            if (state == STATE_READ_B) counter <= counter + 1;
          end
          
          default: begin end
        endcase
        data_ready <= 0;  // Clear the data_ready flag
      end
      
      // Compute matrix multiplication when we have all inputs
      if (state == STATE_COMPUTE) begin
        // Standard 2x2 matrix multiply
        C00 <= A0 * B0 + A1 * B2;
        C01 <= A0 * B1 + A1 * B3;
        C10 <= A2 * B0 + A3 * B2;
        C11 <= A2 * B1 + A3 * B3;
        
        // Prepare output buffer with results
        output_buffer[0] <= A0 * B0 + A1 * B2;
        output_buffer[1] <= A0 * B1 + A1 * B3;
        output_buffer[2] <= A2 * B0 + A3 * B2;
        output_buffer[3] <= A2 * B1 + A3 * B3;
        
        state <= STATE_OUTPUT;
        output_index <= 0;
      end
      
      // Handle output completion
      if (state == STATE_OUTPUT && output_index >= 4 && !tx_busy) begin
        state <= STATE_IDLE;  // Return to idle when all data transmitted
      end
    end
  end
  
  // List all unused input signals to prevent warnings
  wire _unused = &{ena, ui_in[7:1], uio_in};

endmodule