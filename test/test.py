# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer, RisingEdge, FallingEdge

@cocotb.test()
async def test_full_matrix_mult_system(dut):
    """
    Test the entire UART to QSPI matrix multiplication system.
    This test interacts only with the top-level UART pins (uart_rx, uart_tx)
    as presented by the top_arty_matrix_mult module instantiated in tb.v.
    """
    
    # System clock is 100MHz as defined in top_arty_matrix_mult.v (passed to tb)
    # 1 clock cycle = 10 ns
    clock = Clock(dut.clk, 10, units="ns") 
    cocotb.start_soon(clock.start())
    
    # Reset sequence
    dut.rst_n.value = 0
    dut.uart_rx.value = 1 # Set UART RX idle state during reset
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)
    
    # UART Configuration (matches cfg_divider = 1042 in uart_to_qspi.v)
    # Baud rate = 100 MHz / 1042 = 95969 bps (~9600)
    # Cycles per bit = 1042
    # Cycles per half-bit = 521
    uart_cycles_per_bit = 1042 
    uart_cycles_per_half_bit = 521

    # Test matrices
    matrix_a = [1, 2, 3, 4]  # A = [[1, 2], [3, 4]]
    matrix_b = [5, 6, 7, 8]  # B = [[5, 6], [7, 8]]
    
    # Function to send a byte over UART (to dut.uart_rx)
    async def send_uart_byte(byte_to_send):
        cocotb.log.info(f"UART TX: Sending byte {byte_to_send:02X}")
        # Start bit (0)
        dut.uart_rx.value = 0
        await ClockCycles(dut.clk, uart_cycles_per_bit)
        
        # Data bits (LSB first)
        for i in range(8):
            bit = (byte_to_send >> i) & 1
            dut.uart_rx.value = bit
            await ClockCycles(dut.clk, uart_cycles_per_bit)
            
        # Stop bit (1)
        dut.uart_rx.value = 1
        await ClockCycles(dut.clk, uart_cycles_per_bit)
        # Keep idle high after stop bit - Increase delay
        cocotb.log.debug(f"UART TX: Adding inter-byte delay ({uart_cycles_per_bit * 2} cycles)")
        await ClockCycles(dut.clk, uart_cycles_per_bit * 2) # Increased delay between bytes


    # Function to receive a byte over UART (from dut.uart_tx)
    async def receive_uart_byte():
        cocotb.log.info("UART RX: Waiting for start bit...")
        # Wait for start bit (falling edge)
        await FallingEdge(dut.uart_tx) 
        cocotb.log.debug("UART RX: Detected start bit (0)")

        # Wait for middle of start bit
        await ClockCycles(dut.clk, uart_cycles_per_half_bit) 
        
        # Verify start bit is still low
        if dut.uart_tx.value != 0:
             raise TestFailure("UART RX: Did not detect low start bit in the middle.")

        byte_received = 0
        # Read data bits (LSB first)
        for i in range(8):
            await ClockCycles(dut.clk, uart_cycles_per_bit) 
            bit = dut.uart_tx.value
            byte_received |= (bit.integer << i) # Use .integer for bit conversion
            cocotb.log.debug(f"UART RX: Received data bit {i}: {bit}")
        
        # Wait for stop bit
        await ClockCycles(dut.clk, uart_cycles_per_bit)
        cocotb.log.debug(f"UART RX: Stop bit value: {dut.uart_tx.value}")
        if dut.uart_tx.value != 1:
             raise TestFailure("UART RX: Did not detect high stop bit.")

        cocotb.log.info(f"UART RX: Received byte {byte_received:02X}")
        return byte_received

    # --- Start Test ---
    
    # Ensure UART RX is idle (high) before starting
    dut.uart_rx.value = 1
    await ClockCycles(dut.clk, uart_cycles_per_bit * 2) # Wait a couple of bit times

    # Send matrix A
    cocotb.log.info("Sending Matrix A...")
    for value in matrix_a:
        await send_uart_byte(value)
    
    # Send matrix B
    cocotb.log.info("Sending Matrix B...")
    for value in matrix_b:
        await send_uart_byte(value)
    
    cocotb.log.info("Matrices sent. Waiting for computation and UART response...")
    
    # Allow time for computation and UART response.
    # This needs to be long enough for:
    # - UART RX B complete
    # - uart_to_qspi sending B via QSPI
    # - tt_um_qspi_matrix_mult computing C
    # - uart_to_qspi reading C via QSPI (state 5) - involves 4 bytes * 2 nibbles/byte * clock cycles
    # - uart_to_qspi sending C via UART (state 0 -> 1 -> ... -> 0 in retn_state for each byte)
    # Let's increase the wait time substantially. 
    # Each UART byte takes ~10 * 1042 cycles = ~10k cycles. Sending/receiving QSPI also takes time.
    # Let's try 250,000 cycles.
    wait_cycles = 250000
    cocotb.log.info(f"Waiting {wait_cycles} clock cycles...")
    await ClockCycles(dut.clk, wait_cycles)

    # Receive the result matrix C
    cocotb.log.info("Attempting to receive result Matrix C...")
    result = []
    try:
        for i in range(4):
            cocotb.log.info(f"Receiving result byte {i}...")
            byte = await receive_uart_byte()
            result.append(byte)
    except Exception as e:
         cocotb.log.error(f"Error during UART reception: {e}")
         cocotb.log.warning(f"Received data so far: {result}")
         raise TestFailure(f"Failed to receive all result bytes. Error: {e}")


    # Print and verify result
    cocotb.log.info(f"Received Result matrix C (bytes): {result}")
    cocotb.log.info(f"Received Result matrix C (hex): {[f'{x:02X}' for x in result]}")

    # Expected result for [[1,2],[3,4]] × [[5,6],[7,8]] is [[19,22],[43,50]]
    # C00 = 1*5 + 2*7 = 5 + 14 = 19 (0x13)
    # C01 = 1*6 + 2*8 = 6 + 16 = 22 (0x16)
    # C10 = 3*5 + 4*7 = 15 + 28 = 43 (0x2B)
    # C11 = 3*6 + 4*8 = 18 + 32 = 50 (0x32)
    expected = [19, 22, 43, 50] 
    cocotb.log.info(f"Expected Result matrix C (bytes): {expected}")
    cocotb.log.info(f"Expected Result matrix C (hex): {[f'{x:02X}' for x in expected]}")

    assert len(result) == 4, f"Incorrect number of result bytes received: got {len(result)}, expected 4"

    for i in range(4):
        assert result[i] == expected[i], f"Result mismatch at index {i}: got {result[i]} (0x{result[i]:02X}), expected {expected[i]} (0x{expected[i]:02X})"

    cocotb.log.info("Test PASSED!")

    # Add a small final delay
    await ClockCycles(dut.clk, 1000)

    # --- Acknowledge Potential Hardware Issues ---
    cocotb.log.warning("NOTE: The tt_generic_wrapper.v file halves the clock for the core tt_um_qspi_matrix_mult module, "
                       "but the uart_to_qspi.v bridge uses the full clock speed for QSPI communication (qspi_sck). "
                       "This clock domain mismatch on the QSPI interface might cause issues in hardware deployment, "
                       "even if this simulation passes due to generous timing or simulator behavior.")
