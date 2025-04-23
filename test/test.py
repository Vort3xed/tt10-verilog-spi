# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer, RisingEdge, FallingEdge

# UART parameters
CLK_FREQ = 50_000_000  # 50MHz clock
BAUD_RATE = 9600
BIT_PERIOD_NS = (1_000_000_000 / BAUD_RATE)  # in ns
CLK_PERIOD_NS = (1_000_000_000 / CLK_FREQ)   # in ns
CYCLES_PER_BIT = int(BIT_PERIOD_NS / CLK_PERIOD_NS)

@cocotb.test()
async def test_uart_matrix_mult(dut):
    dut._log.info("Starting UART matrix multiplication test")

    # Create system clock (50 MHz)
    clock = Clock(dut.clk, 20, units="ns")
    cocotb.start_soon(clock.start())

    # Initialize UART signals
    dut.ui_in.value = 0xFF  # UART idle is high
    dut.ena.value = 1       # Enable the design

    # Apply reset
    dut._log.info("Applying reset")
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    # Test matrices
    matrix_a = [1, 2, 3, 4]  # A = [[1, 2], [3, 4]]
    matrix_b = [5, 6, 7, 8]  # B = [[5, 6], [7, 8]]
    
    # Expected results
    expected_c00 = 1*5 + 2*7  # 19
    expected_c01 = 1*6 + 2*8  # 22
    expected_c10 = 3*5 + 4*7  # 43
    expected_c11 = 3*6 + 4*8  # 50
    expected = [expected_c00, expected_c01, expected_c10, expected_c11]
    
    # Helper function to send a byte over UART
    async def send_byte_uart(value):
        # Start bit (low)
        dut.ui_in.value = 0x00
        await ClockCycles(dut.clk, CYCLES_PER_BIT)
        
        # 8 data bits (LSB first)
        for i in range(8):
            bit = (value >> i) & 1
            dut.ui_in.value = bit
            await ClockCycles(dut.clk, CYCLES_PER_BIT)
            
        # Stop bit (high)
        dut.ui_in.value = 0xFF
        await ClockCycles(dut.clk, CYCLES_PER_BIT)
        
        # Additional idle time
        await ClockCycles(dut.clk, CYCLES_PER_BIT)
    
    # Helper function to receive a byte over UART
    async def receive_byte_uart():
        # Wait for start bit (low)
        while True:
            if (dut.uo_out.value & 0x01) == 0:
                break
            await ClockCycles(dut.clk, 1)
        
        # Skip to the middle of the start bit
        await ClockCycles(dut.clk, CYCLES_PER_BIT // 2)
        
        # Read 8 data bits
        value = 0
        for i in range(8):
            await ClockCycles(dut.clk, CYCLES_PER_BIT)
            bit = dut.uo_out.value & 0x01
            value |= (bit << i)
            
        # Wait for stop bit
        await ClockCycles(dut.clk, CYCLES_PER_BIT)
        
        # Ensure stop bit is high
        stop_bit = dut.uo_out.value & 0x01
        assert stop_bit == 1, f"Stop bit not high"
        
        return value
    
    # Send matrix A
    dut._log.info("Sending matrix A")
    for value in matrix_a:
        await send_byte_uart(value)
    
    # Send matrix B
    dut._log.info("Sending matrix B")
    for value in matrix_b:
        await send_byte_uart(value)
    
    # Wait for computation
    await ClockCycles(dut.clk, 50)
    
    # Read results
    results = []
    dut._log.info("Reading results")
    for i in range(4):
        result = await receive_byte_uart()
        results.append(result)
        dut._log.info(f"Result {i}: {result} (Expected: {expected[i]})")
        
    # Verify results
    for i in range(4):
        assert results[i] == expected[i], f"Error in result {i}: got {results[i]}, expected {expected[i]}"
    
    dut._log.info("All results match expected values!")