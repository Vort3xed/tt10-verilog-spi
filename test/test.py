# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer, RisingEdge, FallingEdge

@cocotb.test()
async def test_spi_matrix_mult(dut):
    dut._log.info("Starting SPI matrix multiplication test")

    # Create system clock (100 MHz)
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Initialize SPI signals
    # ui_in[0] = MOSI, ui_in[1] = CS_N, ui_in[2] = SCK
    dut.ui_in.value = 0x02  # CS high (inactive), others low
    dut.uio_in.value = 0x00
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
    print("Expected Answers: " + str(expected))
    
    # Start SPI transaction
    dut._log.info("Starting SPI transaction")
    
    # Helper function to send a byte over SPI
    async def send_byte_spi(value):
        for bit_idx in range(7, -1, -1):  # MSB first
            bit_val = (value >> bit_idx) & 0x1
            
            # Set MOSI with CS low
            dut.ui_in.value = bit_val  # MOSI = bit_val, CS = 0, SCK = 0
            await ClockCycles(dut.clk, 1)
            
            # Clock high
            dut.ui_in.value = bit_val | 0x04  # Set SCK high
            await ClockCycles(dut.clk, 1)
            
            # Clock low
            dut.ui_in.value = bit_val  # Set SCK low
            await ClockCycles(dut.clk, 1)
    
    # Helper function to receive a byte over SPI
    async def receive_byte_spi():
        result = 0
        for bit_idx in range(7, -1, -1):  # MSB first
            # Clock high with CS low
            dut.ui_in.value = 0x04  # SCK high, CS low, MOSI low
            await ClockCycles(dut.clk, 1)
            
            # Sample MISO on clock high
            miso_bit = (dut.uo_out.value & 0x01)
            result = (result << 1) | miso_bit
            
            # Clock low
            dut.ui_in.value = 0x00  # SCK low, CS low, MOSI low
            await ClockCycles(dut.clk, 1)
            
        return result
    
    # Activate CS (active low)
    dut.ui_in.value = 0x00  # CS low, SCK low, MOSI low
    await ClockCycles(dut.clk, 2)
    
    # Send matrix A
    dut._log.info("Sending matrix A")
    for value in matrix_a:
        await send_byte_spi(value)
    
    # Send matrix B
    dut._log.info("Sending matrix B")
    for value in matrix_b:
        await send_byte_spi(value)
    
    # Wait for computation
    await ClockCycles(dut.clk, 10)
    
    # Read results
    results = []
    dut._log.info("Reading results")
    for i in range(4):
        value = await receive_byte_spi()
        results.append(value)
        dut._log.info(f"Result {i}: {value}")
    
    # Release CS
    dut.ui_in.value = 0x02  # CS high
    await ClockCycles(dut.clk, 5)
    
    # Verify results
    for i, (expected_val, actual_val) in enumerate(zip(expected, results)):
        assert expected_val == actual_val, f"Mismatch at index {i}: expected {expected_val}, got {actual_val}"
    
    dut._log.info("SPI matrix multiplication test passed!")