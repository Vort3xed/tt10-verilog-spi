/*
 * Copyright (c) 2024 Agneya Tharun 
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_spi_matrix_mult (
    input  wire [7:0] ui_in,    // [0] = spi_mosi, [1] = spi_cs_n, [2] = spi_clk
    output wire [7:0] uo_out,   // [0] = spi_miso
    input  wire [7:0] uio_in,   
    output wire [7:0] uio_out,  
    output wire [7:0] uio_oe,   
    input  wire       ena,      // Always 1 when design is powered
    input  wire       clk,      // System clock
    input  wire       rst_n     // Active-low reset
);

  // Extract SPI signals from input pins
  wire spi_mosi = ui_in[0];
  wire spi_cs_n = ui_in[1];
  wire spi_clk = ui_in[2];
  
  // Drive MISO output
  reg spi_miso;
  assign uo_out = {7'b0000000, spi_miso};
  
  // All bidirectional pins are inputs
  assign uio_oe = 8'b00000000;
  assign uio_out = 8'b00000000;
  
  // Internal state definitions
  localparam STATE_IDLE = 3'd0,
             STATE_READ_A = 3'd1,
             STATE_READ_B = 3'd2, 
             STATE_COMPUTE = 3'd3,
             STATE_PREPARE_OUTPUT = 3'd4,
             STATE_OUTPUT = 3'd5;

  // Registers for state machine and data
  reg [2:0] state;
  reg [2:0] counter;      // Element counter (0-3)
  reg [2:0] bit_counter;  // Bit position counter (0-7)
  
  // Matrix storage (8-bit values)
  reg [7:0] A0, A1, A2, A3;   // Elements for matrix A
  reg [7:0] B0, B1, B2, B3;   // Elements for matrix B
  reg [15:0] C00, C01, C10, C11; // Full-precision intermediate products
  
  // Shift register for input/output
  reg [7:0] shift_reg;
  
  // SPI clock edge detection
  reg spi_clk_prev;
  wire spi_clk_posedge = spi_clk && !spi_clk_prev;
  wire spi_clk_negedge = !spi_clk && spi_clk_prev;
  
  // Sequential logic
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= STATE_IDLE;
      counter <= 0;
      bit_counter <= 0;
      A0 <= 0; A1 <= 0; A2 <= 0; A3 <= 0;
      B0 <= 0; B1 <= 0; B2 <= 0; B3 <= 0;
      C00 <= 0; C01 <= 0; C10 <= 0; C11 <= 0;
      spi_miso <= 0;
      spi_clk_prev <= 0;
      shift_reg <= 0;
    end else begin
      // Update previous clock for edge detection
      spi_clk_prev <= spi_clk;
      
      case (state)
        // Wait for CS to go low to begin transaction
        STATE_IDLE: begin
          if (!spi_cs_n) begin
            state <= STATE_READ_A;
            counter <= 0;
            bit_counter <= 7; // Start with MSB
          end
        end
        
        // Read matrix A (1 bit at a time)
        STATE_READ_A: begin
          if (spi_clk_posedge) begin
            // Shift in MOSI data
            shift_reg <= {shift_reg[6:0], spi_mosi};
            
            if (bit_counter == 0) begin
              // We've received a full byte
              bit_counter <= 7;
              
              case (counter)
                0: begin A0 <= {shift_reg[6:0], spi_mosi}; counter <= counter + 1; end
                1: begin A1 <= {shift_reg[6:0], spi_mosi}; counter <= counter + 1; end
                2: begin A2 <= {shift_reg[6:0], spi_mosi}; counter <= counter + 1; end
                3: begin 
                   A3 <= {shift_reg[6:0], spi_mosi}; 
                   counter <= 0;
                   state <= STATE_READ_B;
                end
              endcase
            end else begin
              bit_counter <= bit_counter - 1;
            end
          end
        end
        
        // Read matrix B (1 bit at a time)
        STATE_READ_B: begin
          if (spi_clk_posedge) begin
            // Shift in MOSI data
            shift_reg <= {shift_reg[6:0], spi_mosi};
            
            if (bit_counter == 0) begin
              // We've received a full byte
              bit_counter <= 7;
              
              case (counter)
                0: begin B0 <= {shift_reg[6:0], spi_mosi}; counter <= counter + 1; end
                1: begin B1 <= {shift_reg[6:0], spi_mosi}; counter <= counter + 1; end
                2: begin B2 <= {shift_reg[6:0], spi_mosi}; counter <= counter + 1; end
                3: begin 
                   B3 <= {shift_reg[6:0], spi_mosi}; 
                   counter <= 0;
                   state <= STATE_COMPUTE;
                end
              endcase
            end else begin
              bit_counter <= bit_counter - 1;
            end
          end
        end
        
        // Compute matrix multiplication 
        STATE_COMPUTE: begin
          // Standard 2x2 matrix multiply
          C00 <= A0 * B0 + A1 * B2;
          C01 <= A0 * B1 + A1 * B3;
          C10 <= A2 * B0 + A3 * B2;
          C11 <= A2 * B1 + A3 * B3;
          state <= STATE_PREPARE_OUTPUT;
        end
        
        // Prepare output - ensure C00 is ready before starting SPI transfer
        STATE_PREPARE_OUTPUT: begin
          counter <= 0;
          bit_counter <= 7;
          
          // Load C00 into the shift register and preload first bit
          shift_reg <= C00[7:0];
          spi_miso <= C00[7];
          state <= STATE_OUTPUT;
        end
        
        // Output results
        STATE_OUTPUT: begin
          // On falling edge, prepare the next bit for the upcoming rising edge
          if (spi_clk_negedge) begin
            if (bit_counter == 0) begin
              // Prepare for next byte
              bit_counter <= 7;
              
              case (counter)
                0: begin 
                   shift_reg <= C01[7:0]; 
                   counter <= counter + 1;
                   spi_miso <= C01[7]; // Preload first bit of next byte
                end
                1: begin 
                   shift_reg <= C10[7:0]; 
                   counter <= counter + 1;
                   spi_miso <= C10[7]; // Preload first bit of next byte
                end
                2: begin 
                   shift_reg <= C11[7:0]; 
                   counter <= counter + 1;
                   spi_miso <= C11[7]; // Preload first bit of next byte
                end
                3: begin 
                   shift_reg <= 8'h00; 
                   counter <= 0;
                   state <= STATE_IDLE;
                   spi_miso <= 0; // Clear MISO when finished
                end
              endcase
            end else begin
              // Prepare next bit
              bit_counter <= bit_counter - 1;
              spi_miso <= shift_reg[bit_counter - 1];
            end
          end
        end
        
        default: state <= STATE_IDLE;
      endcase
      
      // If CS goes high at any point, return to idle
      if (spi_cs_n) begin
        state <= STATE_IDLE;
        spi_miso <= 0;
      end
    end
  end

  // List all unused input signals to prevent warnings
  wire _unused = &{ena, ui_in[7:3], uio_in};

endmodule