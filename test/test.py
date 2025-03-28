# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer, RisingEdge, FallingEdge

@cocotb.test()
async def test_full_matrix_mult_system(dut):
    """Test the entire UART to QSPI matrix multiplication system"""
    
    # Create clock
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)
    
    # Test matrices
    matrix_a = [1, 2, 3, 4]  # A = [[1, 2], [3, 4]]
    matrix_b = [5, 6, 7, 8]  # B = [[5, 6], [7, 8]]
    
    # Function to send a byte over UART
    async def send_uart_byte(byte):
        # Start bit (0)
        dut.uart_rx.value = 0
        await ClockCycles(dut.clk, 1042)  # Wait for one bit time at your baud rate
        
        # Data bits (LSB first)
        for i in range(8):
            bit = (byte >> i) & 1
            dut.uart_rx.value = bit
            await ClockCycles(dut.clk, 1042)
            
        # Stop bit (1)
        dut.uart_rx.value = 1
        await ClockCycles(dut.clk, 1042)
    
    # Send matrix A
    for value in matrix_a:
        await send_uart_byte(value)
    
    # Send matrix B
    for value in matrix_b:
        await send_uart_byte(value)
    
    # Allow time for computation and UART response
    await ClockCycles(dut.clk, 10000)

    # Function to receive a byte over UART
    async def receive_uart_byte():
        # Wait for start bit (0)
        while dut.uart_tx.value == 1:
            await ClockCycles(dut.clk, 10)
        
        # Wait for middle of start bit
        await ClockCycles(dut.clk, 521) # Half bit time
        
        byte = 0
        # Read data bits (LSB first)
        for i in range(8):
            await ClockCycles(dut.clk, 1042) # Full bit time
            bit = dut.uart_tx.value
            byte |= (bit << i)
        
        # Wait for stop bit
        await ClockCycles(dut.clk, 1042)
        
        return byte

    # Receive the result matrix
    result = []
    for _ in range(4):
        result.append(await receive_uart_byte())

    # Print and verify result
    print(f"Result matrix: {result}")

    # Expected result for [[1,2],[3,4]] × [[5,6],[7,8]] is [[19,22],[43,50]]
    expected = [19, 22, 43, 50]
    for i in range(4):
        assert result[i] == expected[i], f"Result mismatch at position {i}: got {result[i]}, expected {expected[i]}"