/*
 * Copyright (c) 2024 Agneya Tharun 
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_qspi_matrix_mult (
    input  wire [7:0] ui_in,    // [3:0] = qspi_io_in, [4] = qspi_cs_n, [5] = qspi_clk
    output wire [7:0] uo_out,   // [3:0] = qspi_io_out
    input  wire [7:0] uio_in,   
    output wire [7:0] uio_out,  
    output wire [7:0] uio_oe,   // Output enable for QSPI bidirectional pins
    input  wire       ena,      // Always 1 when design is powered
    input  wire       clk,      // System clock
    input  wire       rst_n     // Active-low reset
);

  // Extract QSPI signals from input pins
  wire [3:0] qspi_io_in = ui_in[3:0];
  wire qspi_cs_n = ui_in[4];
  wire qspi_clk = ui_in[5];
  
  // Drive only the lower 4 bits for QSPI IO output
  reg [3:0] qspi_io_out;
  assign uo_out = {4'b0000, qspi_io_out};
  
  // Output enable (active during transmission)
  reg [3:0] qspi_io_oe;
  assign uio_oe = {4'b0000, qspi_io_oe};
  
  // Internal state definitions
  localparam STATE_IDLE = 3'd0,
             STATE_READ_A = 3'd1,
             STATE_READ_B = 3'd2, 
             STATE_COMPUTE = 3'd3,
             STATE_OUTPUT = 3'd4;

  // Registers for state machine and data
  reg [2:0] state;
  reg [2:0] counter;
  reg [2:0] nibble_counter; // Tracks which 4-bit part we're processing
  
  // Matrix storage (8-bit values)
  reg [7:0] A0, A1, A2, A3;   // Elements for matrix A
  reg [7:0] B0, B1, B2, B3;   // Elements for matrix B
  reg [15:0] C00, C01, C10, C11; // Full-precision intermediate products
  
  // Temporary registers for storing half-bytes during input
  reg [3:0] nibble_buffer;
  
  // QSPI clock edge detection
  reg qspi_clk_prev;
  wire qspi_clk_posedge = qspi_clk && !qspi_clk_prev;
  wire qspi_clk_negedge = !qspi_clk && qspi_clk_prev;
  
  // Sequential logic
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= STATE_IDLE;
      counter <= 0;
      nibble_counter <= 0;
      A0 <= 0; A1 <= 0; A2 <= 0; A3 <= 0;
      B0 <= 0; B1 <= 0; B2 <= 0; B3 <= 0;
      C00 <= 0; C01 <= 0; C10 <= 0; C11 <= 0;
      qspi_io_out <= 4'b0000;
      qspi_io_oe <= 4'b0000;
      qspi_clk_prev <= 0;
      nibble_buffer <= 0;
    end else begin
      // Update previous clock for edge detection
      qspi_clk_prev <= qspi_clk;
      
      // Default OE to off unless explicitly set
      qspi_io_oe <= 4'b0000;
      
      case (state)
        // Wait for CS to go low to begin transaction
        STATE_IDLE: begin
          if (!qspi_cs_n) begin
            state <= STATE_READ_A;
            counter <= 0;
            nibble_counter <= 0;
          end
        end
        
        // Read matrix A (4 bits at a time)
        STATE_READ_A: begin
          if (qspi_clk_posedge) begin
            case (counter)
              0: begin
                if (nibble_counter == 0) begin
                  nibble_buffer <= qspi_io_in;
                  nibble_counter <= 1;
                end else begin
                  A0 <= {nibble_buffer, qspi_io_in};
                  nibble_counter <= 0;
                  counter <= counter + 1;
                end
              end
              1: begin
                if (nibble_counter == 0) begin
                  nibble_buffer <= qspi_io_in;
                  nibble_counter <= 1;
                end else begin
                  A1 <= {nibble_buffer, qspi_io_in};
                  nibble_counter <= 0;
                  counter <= counter + 1;
                end
              end
              2: begin
                if (nibble_counter == 0) begin
                  nibble_buffer <= qspi_io_in;
                  nibble_counter <= 1;
                end else begin
                  A2 <= {nibble_buffer, qspi_io_in};
                  nibble_counter <= 0;
                  counter <= counter + 1;
                end
              end
              3: begin
                if (nibble_counter == 0) begin
                  nibble_buffer <= qspi_io_in;
                  nibble_counter <= 1;
                end else begin
                  A3 <= {nibble_buffer, qspi_io_in};
                  nibble_counter <= 0;
                  counter <= 0;
                  state <= STATE_READ_B;
                end
              end
            endcase
          end
        end
        
        // Read matrix B (4 bits at a time)
        STATE_READ_B: begin
          if (qspi_clk_posedge) begin
            case (counter)
              0: begin
                if (nibble_counter == 0) begin
                  nibble_buffer <= qspi_io_in;
                  nibble_counter <= 1;
                end else begin
                  B0 <= {nibble_buffer, qspi_io_in};
                  nibble_counter <= 0;
                  counter <= counter + 1;
                end
              end
              1: begin
                if (nibble_counter == 0) begin
                  nibble_buffer <= qspi_io_in;
                  nibble_counter <= 1;
                end else begin
                  B1 <= {nibble_buffer, qspi_io_in};
                  nibble_counter <= 0;
                  counter <= counter + 1;
                end
              end
              2: begin
                if (nibble_counter == 0) begin
                  nibble_buffer <= qspi_io_in;
                  nibble_counter <= 1;
                end else begin
                  B2 <= {nibble_buffer, qspi_io_in};
                  nibble_counter <= 0;
                  counter <= counter + 1;
                end
              end
              3: begin
                if (nibble_counter == 0) begin
                  nibble_buffer <= qspi_io_in;
                  nibble_counter <= 1;
                end else begin
                  B3 <= {nibble_buffer, qspi_io_in};
                  nibble_counter <= 0;
                  counter <= 0;
                  state <= STATE_COMPUTE;
                end
              end
            endcase
          end
        end
        
        // Compute matrix multiplication
        STATE_COMPUTE: begin
          // Standard 2x2 matrix multiply
          C00 <= A0 * B0 + A1 * B2;
          C01 <= A0 * B1 + A1 * B3;
          C10 <= A2 * B0 + A3 * B2;
          C11 <= A2 * B1 + A3 * B3;
          state <= STATE_OUTPUT;
          counter <= 0;
          nibble_counter <= 0;
        end
        
        // Output each cell over successive clock cycles (4 bits at a time)
        STATE_OUTPUT: begin
          // Set output enable since we're sending data back
          qspi_io_oe <= 4'b1111;
          
          if (qspi_clk_negedge) begin
            case (counter)
              0: begin
                if (nibble_counter == 0) begin
                  qspi_io_out <= C00[7:4];
                  nibble_counter <= 1;
                end else begin
                  qspi_io_out <= C00[3:0];
                  nibble_counter <= 0;
                  counter <= counter + 1;
                end
              end
              1: begin
                if (nibble_counter == 0) begin
                  qspi_io_out <= C01[7:4];
                  nibble_counter <= 1;
                end else begin
                  qspi_io_out <= C01[3:0];
                  nibble_counter <= 0;
                  counter <= counter + 1;
                end
              end
              2: begin
                if (nibble_counter == 0) begin
                  qspi_io_out <= C10[7:4];
                  nibble_counter <= 1;
                end else begin
                  qspi_io_out <= C10[3:0];
                  nibble_counter <= 0;
                  counter <= counter + 1;
                end
              end
              3: begin
                if (nibble_counter == 0) begin
                  qspi_io_out <= C11[7:4];
                  nibble_counter <= 1;
                end else begin
                  qspi_io_out <= C11[3:0];
                  nibble_counter <= 0;
                  counter <= counter + 1;
                  state <= STATE_IDLE;
                end
              end
            endcase
          end
        end
        
        default: state <= STATE_IDLE;
      endcase
      
      // If CS goes high at any point, return to idle
      if (qspi_cs_n) begin
        state <= STATE_IDLE;
        qspi_io_oe <= 4'b0000;
      end
    end
  end

  // List all unused input signals to prevent warnings
  wire _unused = &{ena, ui_in[7:6]};

endmodule