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
  assign uio_out = 8'b0;  // Not using these outputs
  
  // Internal state definitions
  localparam STATE_IDLE = 3'd0,
             STATE_READ_A = 3'd1,
             STATE_READ_B = 3'd2, 
             STATE_COMPUTE = 3'd3,
             STATE_OUTPUT = 3'd4;

  // Registers for state machine and data
  reg [2:0] state;
  reg [2:0] byte_counter;  // Counts which value we're on (0-3 for each matrix)
  reg nibble_flag;         // 0 = high nibble, 1 = low nibble
  
  // Matrix storage (8-bit values)
  reg [7:0] A[0:3];        // Elements for matrix A: A[0]=A0, A[1]=A1, etc.
  reg [7:0] B[0:3];        // Elements for matrix B
  reg [7:0] C[0:3];        // Elements for result matrix C
  
  // Temporary register for storing high nibble
  reg [3:0] high_nibble;
  
  // Output control
  reg [1:0] output_counter;  // Which result to output
  
  // QSPI clock edge detection
  reg qspi_clk_prev;
  wire qspi_clk_posedge = qspi_clk && !qspi_clk_prev;
  wire qspi_clk_negedge = !qspi_clk && qspi_clk_prev;
  
  // Sequential logic
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= STATE_IDLE;
      byte_counter <= 0;
      nibble_flag <= 0;
      high_nibble <= 0;
      output_counter <= 0;
      
      // Initialize matrices
      A[0] <= 0; A[1] <= 0; A[2] <= 0; A[3] <= 0;
      B[0] <= 0; B[1] <= 0; B[2] <= 0; B[3] <= 0;
      C[0] <= 0; C[1] <= 0; C[2] <= 0; C[3] <= 0;
      
      qspi_io_out <= 4'b0000;
      qspi_io_oe <= 4'b0000;
      qspi_clk_prev <= 0;
    end else begin
      // Update previous clock for edge detection
      qspi_clk_prev <= qspi_clk;
      
      // Default settings
      qspi_io_oe <= 4'b0000;
      
      case (state)
        STATE_IDLE: begin
          // Reset counters when entering IDLE
          byte_counter <= 0;
          nibble_flag <= 0;
          
          // Wait for chip select to be asserted (active low)
          if (!qspi_cs_n) begin
            state <= STATE_READ_A;
            $display("STATE_IDLE: CS asserted, moving to STATE_READ_A");
          end
        end
        
        STATE_READ_A: begin
          if (qspi_clk_posedge) begin
            if (!nibble_flag) begin
              // Store high nibble
              high_nibble <= qspi_io_in;
              nibble_flag <= 1;
              $display("STATE_READ_A: High nibble %h for A[%d]", qspi_io_in, byte_counter);
            end else begin
              // Complete byte with low nibble and store
              A[byte_counter] <= {high_nibble, qspi_io_in};
              nibble_flag <= 0;
              $display("STATE_READ_A: Stored A[%d] = %h", byte_counter, {high_nibble, qspi_io_in});
              
              // Move to next byte or state
              if (byte_counter == 3) begin
                byte_counter <= 0;
                state <= STATE_READ_B;
                $display("STATE_READ_A: Matrix A complete, moving to STATE_READ_B");
              end else begin
                byte_counter <= byte_counter + 1;
              end
            end
          end
          
          // If CS goes inactive, return to IDLE
          if (qspi_cs_n) begin
            state <= STATE_IDLE;
            $display("STATE_READ_A: CS deasserted, moving to STATE_IDLE");
          end
        end
        
        STATE_READ_B: begin
          if (qspi_clk_posedge) begin
            if (!nibble_flag) begin
              // Store high nibble
              high_nibble <= qspi_io_in;
              nibble_flag <= 1;
              $display("STATE_READ_B: High nibble %h for B[%d]", qspi_io_in, byte_counter);
            end else begin
              // Complete byte with low nibble and store
              B[byte_counter] <= {high_nibble, qspi_io_in};
              nibble_flag <= 0;
              $display("STATE_READ_B: Stored B[%d] = %h", byte_counter, {high_nibble, qspi_io_in});
              
              // Move to next byte or state
              if (byte_counter == 3) begin
                byte_counter <= 0;
                state <= STATE_COMPUTE;
                $display("STATE_READ_B: Matrix B complete, moving to STATE_COMPUTE");
              end else begin
                byte_counter <= byte_counter + 1;
              end
            end
          end
          
          // If CS goes inactive, return to IDLE
          if (qspi_cs_n) begin
            state <= STATE_IDLE;
            $display("STATE_READ_B: CS deasserted, moving to STATE_IDLE");
          end
        end
        
        STATE_COMPUTE: begin
          // Compute matrix multiplication: C = A * B
          // C00 = A00*B00 + A01*B10
          C[0] <= A[0] * B[0] + A[1] * B[2];
          // C01 = A00*B01 + A01*B11
          C[1] <= A[0] * B[1] + A[1] * B[3];
          // C10 = A10*B00 + A11*B10
          C[2] <= A[2] * B[0] + A[3] * B[2];
          // C11 = A10*B01 + A11*B11
          C[3] <= A[2] * B[1] + A[3] * B[3];
          
          state <= STATE_OUTPUT;
          output_counter <= 0;
          $display("STATE_COMPUTE: Matrix multiplication complete, moving to STATE_OUTPUT");
        end
        
        STATE_OUTPUT: begin
          // Set output enable
          qspi_io_oe <= 4'b1111;
          
          if (qspi_clk_posedge) begin
            if (!nibble_flag) begin
              // Output high nibble
              qspi_io_out <= C[output_counter][7:4];
              nibble_flag <= 1;
              $display("STATE_OUTPUT: Sending high nibble %h of C[%d]", C[output_counter][7:4], output_counter);
            end else begin
              // Output low nibble
              qspi_io_out <= C[output_counter][3:0];
              nibble_flag <= 0;
              $display("STATE_OUTPUT: Sending low nibble %h of C[%d]", C[output_counter][3:0], output_counter);
              
              // Move to next result element
              if (output_counter == 3) begin
                state <= STATE_IDLE;
                $display("STATE_OUTPUT: Matrix C output complete, moving to STATE_IDLE");
              end else begin
                output_counter <= output_counter + 1;
              end
            end
          end
          
          // If CS goes inactive, return to IDLE
          if (qspi_cs_n) begin
            state <= STATE_IDLE;
            $display("STATE_OUTPUT: CS deasserted, moving to STATE_IDLE");
          end
        end
        
        // default: state <= STATE_IDLE;
      endcase
    end
  end

  // List all unused input signals to prevent warnings
  wire _unused = &{ena, ui_in[7:6], uio_in};

endmodule