# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer, RisingEdge, FallingEdge, Combine, First

# Helper function to simulate SPI master transaction
# Add to the test.py file

# This function should completely replace the existing spi_transaction function

async def spi_transaction(dut, tx_data_list):
    """
    Simulates a standard SPI transaction (Mode 0: CPOL=0, CPHA=0).
    Sends bytes from tx_data_list and returns received bytes.
    """
    dut._log.info(f"Starting SPI transaction. Sending: {tx_data_list}")
    rx_data_list = []
    spi_clk_period_ns = 40  # 25 MHz SPI clock

    # Assert CS low (active)
    dut.ui_in.value = (dut.ui_in.value & ~0x10)
    await Timer(spi_clk_period_ns / 2, units="ns")

    # Process each byte
    for tx_byte in tx_data_list:
        rx_byte = 0
        
        # Process each bit (MSB first)
        for bit_idx in range(8):
            # Extract current bit to send (MSB first)
            tx_bit = (tx_byte >> (7 - bit_idx)) & 0x01
            
            # Set SDI (MOSI) value
            dut.ui_in.value = (dut.ui_in.value & ~0x01) | tx_bit
            
            # SCK low phase
            dut.ui_in.value = dut.ui_in.value & ~0x20  # Clear SCK
            await Timer(spi_clk_period_ns / 2, units="ns")
            
            # SCK high phase - slave samples SDI, master samples SDO
            dut.ui_in.value = dut.ui_in.value | 0x20   # Set SCK
            await Timer(spi_clk_period_ns / 4, units="ns")
            
            # Sample SDO (MISO)
            sdo_bit = (dut.uo_out.value & 0x01)
            
            # Shift received bit into rx_byte (MSB first)
            rx_byte = (rx_byte << 1) | sdo_bit
            
            await Timer(spi_clk_period_ns / 4, units="ns")
        
        rx_data_list.append(rx_byte)
    
    # Add dummy bytes to receive the computed result 
    # (need 4 more bytes after sending 8 bytes of input)
    if len(tx_data_list) >= 8:
        # Send additional dummy bytes to clock out the result
        for _ in range(4):
            rx_byte = 0
            for bit_idx in range(8):
                # Just toggle clock with SDI=0
                dut.ui_in.value = dut.ui_in.value & ~0x01  # SDI=0
                
                # SCK low phase
                dut.ui_in.value = dut.ui_in.value & ~0x20
                await Timer(spi_clk_period_ns / 2, units="ns")
                
                # SCK high phase
                dut.ui_in.value = dut.ui_in.value | 0x20
                await Timer(spi_clk_period_ns / 4, units="ns")
                
                # Sample SDO
                sdo_bit = (dut.uo_out.value & 0x01)
                rx_byte = (rx_byte << 1) | sdo_bit
                
                await Timer(spi_clk_period_ns / 4, units="ns")
            
            rx_data_list.append(rx_byte)
    
    # Deassert CS
    dut.ui_in.value = dut.ui_in.value | 0x10  # Set CS high
    dut.ui_in.value = dut.ui_in.value & ~0x20  # SCK low after transaction
    
    dut._log.info(f"Finished SPI transaction. Received: {rx_data_list}")
    return rx_data_list


@cocotb.test()
async def test_spi_matrix_mult(dut):
    dut._log.info("Starting Standard SPI matrix multiplication test")

    # Create system clock (e.g., 50 MHz if wrapper divides by 2 from 100MHz)
    # The testbench drives the wrapper clock directly. Let's assume 50MHz for project clk.
    # The wrapper divides the input clock by 2. So drive clk at 100MHz.
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # Initialize inputs
    dut.ui_in.value = 0x10  # CS high initially, SCK/SDI low
    dut.uio_in.value = 0x00 # Not used by SPI core
    dut.ena.value = 1       # Enable the design

    # Apply reset
    dut._log.info("Applying reset")
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5) # Wait for reset to release

    # Test matrices
    matrix_a = [1, 2, 3, 4]  # A = [[1, 2], [3, 4]]
    matrix_b = [5, 6, 7, 8]  # B = [[5, 6], [7, 8]]

    # Expected results (8-bit LSB of the full 16-bit result)
    # C00 = 1*5 + 2*7 = 5 + 14 = 19
    # C01 = 1*6 + 2*8 = 6 + 16 = 22
    # C10 = 3*5 + 4*7 = 15 + 28 = 43
    # C11 = 3*6 + 4*8 = 18 + 32 = 50
    expected_results_lsb = [19, 22, 43, 50]

    # Combine matrices A and B for sending
    data_to_send = matrix_a + matrix_b

    # The design needs to receive all input bytes before it can send results.
    # We need to send dummy bytes while receiving the results.
    # Send A and B (8 bytes), then send 4 dummy bytes (e.g., 0x00) to clock out the 4 result bytes.
    data_to_send += [0x00] * len(expected_results_lsb)

    # Perform the SPI transaction
    received_data = await spi_transaction(dut, data_to_send)

    # Extract the actual results received (last 4 bytes)
    actual_results = received_data[-len(expected_results_lsb):]

    dut._log.info(f"Data Sent    : {data_to_send}")
    dut._log.info(f"Data Received: {received_data}")
    dut._log.info(f"Expected LSB : {expected_results_lsb}")
    dut._log.info(f"Actual LSB   : {actual_results}")

    # Verify results
    assert len(actual_results) == len(expected_results_lsb), \
        f"Incorrect number of results received: expected {len(expected_results_lsb)}, got {len(actual_results)}"

    for i, (expected_val, actual_val) in enumerate(zip(expected_results_lsb, actual_results)):
        assert expected_val == actual_val, \
            f"Mismatch at result index {i}: expected {expected_val:#04x}, got {actual_val:#04x}"

    dut._log.info("Standard SPI matrix multiplication test passed!")

    # Add a small delay at the end
    await ClockCycles(dut.clk, 10)
