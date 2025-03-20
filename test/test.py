# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer, RisingEdge, FallingEdge

@cocotb.test()
async def test_qspi_matrix_mult(dut):
    dut._log.info("Starting QSPI matrix multiplication test")

    # Create system clock (100 MHz)
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Initialize QSPI signals
    dut.ui_in.value = 0x00  # All inputs low
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
    
    # Start QSPI transaction
    dut._log.info("Starting QSPI transaction")
    
    # Set CS active (low)
    dut.ui_in.value = 0x00
    await ClockCycles(dut.clk, 2)
    
    # Helper function to send a byte over QSPI (4 bits at a time)
    async def send_byte_qspi(value):
        # Send high nibble
        high_nibble = (value >> 4) & 0xF
        dut.ui_in.value = high_nibble  # Set data bits (low 4 bits)
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = high_nibble | 0x20  # Set clock high
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = high_nibble  # Set clock low
        await ClockCycles(dut.clk, 1)
        
        # Send low nibble
        low_nibble = value & 0xF
        dut.ui_in.value = low_nibble  # Set data bits
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = low_nibble | 0x20  # Set clock high
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = low_nibble  # Set clock low
        await ClockCycles(dut.clk, 1)
    
    # Helper function to receive a byte over QSPI
    async def receive_byte_qspi():
        # Set clock high first
        dut.ui_in.value = 0x20  # Clock high with CS low
        await ClockCycles(dut.clk, 2)
        # Now set clock low to trigger the falling edge response
        dut.ui_in.value = 0x00  # Clock low
        await ClockCycles(dut.clk, 2)
        # Read high nibble after falling edge
        high_nibble = dut.uo_out.value & 0xF
        
        # Repeat for low nibble
        dut.ui_in.value = 0x20  # Clock high
        await ClockCycles(dut.clk, 2)
        dut.ui_in.value = 0x00  # Clock low
        await ClockCycles(dut.clk, 2)
        # Read low nibble after falling edge
        low_nibble = dut.uo_out.value & 0xF
        
        return (high_nibble << 4) | low_nibble
    
    # Send matrix A
    dut._log.info("Sending matrix A")
    for value in matrix_a:
        await send_byte_qspi(value)
    
    # Send matrix B
    dut._log.info("Sending matrix B")
    for value in matrix_b:
        await send_byte_qspi(value)
    
    # Wait for computation
    await ClockCycles(dut.clk, 5)
    
    # Read results
    results = []
    dut._log.info("Reading results")
    for i in range(4):
        value = await receive_byte_qspi()
        results.append(value)
        dut._log.info(f"Result {i}: {value}")

    print(f"results array {results}")
    
    # Release CS
    dut.ui_in.value = 0x10  # Set CS high
    await ClockCycles(dut.clk, 5)
    
    # Verify results
    for i, (expected_val, actual_val) in enumerate(zip(expected, results)):
        assert expected_val == actual_val, f"Mismatch at index {i}: expected {expected_val}, got {actual_val}"
    
    dut._log.info("QSPI matrix multiplication test passed!")