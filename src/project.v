/*
 * Copyright (c) 2024 Agneya Tharun
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_spi_matrix_mult (
    input  wire [7:0] ui_in,    // [0] = spi_sdi, [4] = spi_cs_n, [5] = spi_clk 
    output wire [7:0] uo_out,   // [0] = spi_sdo
    input  wire [7:0] uio_in,   // Unused in this SPI implementation
    output wire [7:0] uio_out,  // Unused in this SPI implementation
    output wire [7:0] uio_oe,   // Unused in this SPI implementation
    input  wire       ena,      // Always 1 when design is powered
    input  wire       clk,      // System clock (from wrapper) - Unused now
    input  wire       rst_n     // Active-low reset
);

    // Extract SPI signals from input pins
    wire spi_sdi   = ui_in[0];   // Serial Data In (MOSI)
    wire spi_cs_n  = ui_in[4];   // Chip Select (active low)
    wire spi_clk   = ui_in[5];   // SPI Clock 

    // SPI data output
    reg spi_sdo_reg;
    assign uo_out = {7'b0000000, spi_sdo_reg};

    // Unused bidirectional pins
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    // Matrix storage - each 8-bit element
    reg [7:0] matrix_A [0:3]; // A = [[A00, A01], [A10, A11]]
    reg [7:0] matrix_B [0:3]; // B = [[B00, B01], [B10, B11]]
    reg [7:0] matrix_C [0:3]; // C = A×B = [[C00, C01], [C10, C11]]

    // State machine
    reg [2:0] state;
    localparam IDLE     = 3'd0,
               READ_A   = 3'd1,
               READ_B   = 3'd2,
               COMPUTE  = 3'd3,
               OUTPUT   = 3'd4;

    // Input/output buffer and control registers
    reg [7:0] rx_shift_reg;  // Shift register for receiving bytes
    reg [7:0] tx_shift_reg;  // Shift register for transmitting bytes
    reg [2:0] byte_count;    // Count of bytes received or sent
    reg [2:0] bit_count;     // Bit position within byte (7 down to 0)
    reg compute_done;        // Flag to indicate computation is complete

    // Function to compute one element of the result matrix
    function [7:0] matrix_mul_element;
        input [7:0] a1, a2, b1, b2;
        begin
            matrix_mul_element = a1 * b1 + a2 * b2;
        end
    endfunction

    // Receive on rising edge (SPI Mode 0)
    always @(posedge spi_clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            byte_count <= 0;
            bit_count <= 7;
            rx_shift_reg <= 0;
            compute_done <= 0;
            
            // Initialize matrices
            matrix_A[0] <= 0; matrix_A[1] <= 0; matrix_A[2] <= 0; matrix_A[3] <= 0;
            matrix_B[0] <= 0; matrix_B[1] <= 0; matrix_B[2] <= 0; matrix_B[3] <= 0;
            matrix_C[0] <= 0; matrix_C[1] <= 0; matrix_C[2] <= 0; matrix_C[3] <= 0;
        end
        else if (spi_cs_n) begin
            // When CS is inactive (high), reset state machine
            state <= IDLE;
            byte_count <= 0;
            bit_count <= 7;
            compute_done <= 0;
        end
        else begin
            // Shift in the incoming bit (MSB first)
            rx_shift_reg <= {rx_shift_reg[6:0], spi_sdi};
            
            // Decrement bit counter
            if (bit_count == 0) begin
                // We've received a complete byte
                bit_count <= 7;
                
                case (state)
                    IDLE: begin
                        // First byte starts matrix A input
                        matrix_A[0] <= {rx_shift_reg[6:0], spi_sdi};
                        state <= READ_A;
                        byte_count <= 1; // Already received one byte
                    end
                    
                    READ_A: begin
                        // Store next byte of matrix A
                        matrix_A[byte_count] <= {rx_shift_reg[6:0], spi_sdi};
                        
                        if (byte_count == 3) begin
                            // Matrix A is complete, move to matrix B
                            state <= READ_B;
                            byte_count <= 0;
                        end
                        else begin
                            byte_count <= byte_count + 1;
                        end
                    end
                    
                    READ_B: begin
                        // Store next byte of matrix B
                        matrix_B[byte_count] <= {rx_shift_reg[6:0], spi_sdi};
                        
                        if (byte_count == 3) begin
                            // Matrix B is complete, compute result
                            state <= COMPUTE;
                            byte_count <= 0;
                        end
                        else begin
                            byte_count <= byte_count + 1;
                        end
                    end
                    
                    COMPUTE: begin
                        // Perform matrix multiplication when we have all inputs
                        matrix_C[0] <= matrix_mul_element(matrix_A[0], matrix_A[1], matrix_B[0], matrix_B[2]);
                        matrix_C[1] <= matrix_mul_element(matrix_A[0], matrix_A[1], matrix_B[1], matrix_B[3]);
                        matrix_C[2] <= matrix_mul_element(matrix_A[2], matrix_A[3], matrix_B[0], matrix_B[2]);
                        matrix_C[3] <= matrix_mul_element(matrix_A[2], matrix_A[3], matrix_B[1], matrix_B[3]);
                        
                        state <= OUTPUT;
                        compute_done <= 1;
                        
                        // Load first result byte into tx shift register for output
                        tx_shift_reg <= matrix_mul_element(matrix_A[0], matrix_A[1], matrix_B[0], matrix_B[2]);
                    end
                    
                    OUTPUT: begin
                        if (byte_count < 3) begin
                            // Move to next result byte
                            byte_count <= byte_count + 1;
                            
                            // Load next result byte
                            case (byte_count + 1)
                                1: tx_shift_reg <= matrix_C[1];
                                2: tx_shift_reg <= matrix_C[2];
                                3: tx_shift_reg <= matrix_C[3];
                                default: tx_shift_reg <= 0;
                            endcase
                        end
                    end
                endcase
            end
            else begin
                bit_count <= bit_count - 1;
            end
        end
    end

    // Transmit on falling edge (SPI Mode 0)
    always @(negedge spi_clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_sdo_reg <= 0;
            tx_shift_reg <= 0;
        end
        else if (spi_cs_n) begin
            spi_sdo_reg <= 0;
        end
        else if (state == OUTPUT && compute_done) begin
            // When in OUTPUT state, shift out MSB first
            spi_sdo_reg <= tx_shift_reg[7];
            
            // Setup next bit for next falling edge
            if (bit_count == 7) begin
                // About to send a new byte, load it just after the rising edge
                if (byte_count == 0) tx_shift_reg <= matrix_C[0];
                else if (byte_count == 1) tx_shift_reg <= matrix_C[1];
                else if (byte_count == 2) tx_shift_reg <= matrix_C[2];
                else tx_shift_reg <= matrix_C[3];
            end
            else begin
                // Continue shifting the current byte
                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
            end
        end
        else begin
            spi_sdo_reg <= 0; // Default to 0 when not in output state
        end
    end

    // Unused input signals
    wire _unused = &{ui_in[3:1], ui_in[7:6], uio_in, ena, clk};

endmodule
`default_nettype wire