import time
from pyftdi.spi import SpiController
import numpy as np
from pyftdi.ftdi import Ftdi

class QSPIMatrixMultiplier:
    def __init__(self, ftdi_url=None):
        """Initialize the SPI controller for Arty A7 board connection."""
        # Configure SPI controller
        self.spi_controller = SpiController()
        
        # Try to find the FTDI device automatically if URL not provided
        if ftdi_url is None:
            # List available devices to help with debugging
            print("Searching for FTDI devices...")
            available_devices = Ftdi.find_all()
            
            if not available_devices:
                raise RuntimeError("No FTDI devices found. Is the ARTY A7 board connected?")
            
            # Print available devices to help with debugging
            print("Available FTDI devices:")
            for i, device in enumerate(available_devices):
                print(f"  {i}: {device}")
            
            # For ARTY A7, we typically want the second interface of the FT2232H
            # The first is usually for JTAG programming
            ftdi_url = 'ftdi://ftdi:2232h/2'
            print(f"Using default FTDI URL: {ftdi_url}")
        
        try:
            self.spi_controller.configure(ftdi_url)
            
            # Get SPI port 0, ARTY A7 typically operates at 3.3V, so use mode 0
            # QSPI pins should be connected to PMOD JA or JB on the ARTY
            self.spi = self.spi_controller.get_port(0, freq=1E6, mode=0)
            print("QSPI Matrix Multiplier connected successfully")
        except Exception as e:
            print(f"Connection failed: {e}")
            print("\nTroubleshooting tips:")
            print("1. Make sure your ARTY A7 is connected and powered")
            print("2. Verify the QSPI pins are correctly connected to a PMOD port")
            print("3. Try using a different FTDI URL based on the available devices listed above")
            print("4. If using Windows, ensure the correct FTDI drivers are installed")
            raise
    
    def multiply_matrices(self, matrix_a, matrix_b):
        """Multiply two 2x2 matrices using the FPGA implementation."""
        # Convert matrices to flat list if needed
        if isinstance(matrix_a, np.ndarray):
            a_flat = matrix_a.flatten().tolist()
        else:
            a_flat = [matrix_a[0][0], matrix_a[0][1], matrix_a[1][0], matrix_a[1][1]]
            
        if isinstance(matrix_b, np.ndarray):
            b_flat = matrix_b.flatten().tolist()
        else:
            b_flat = [matrix_b[0][0], matrix_b[0][1], matrix_b[1][0], matrix_b[1][1]]
        
        # Ensure values are 8-bit integers
        a_bytes = bytes([int(x) & 0xFF for x in a_flat])
        b_bytes = bytes([int(x) & 0xFF for x in b_flat])
        
        # Send data and receive result
        write_data = a_bytes + b_bytes
        
        # We expect 4 bytes of result
        result_bytes = bytearray(4)
        
        # Add a small delay to ensure FPGA is ready
        time.sleep(0.01)
        
        # Write and read in a single transaction
        print("Sending data to FPGA...")
        self.spi.exchange(write_data, result_bytes)
        
        # Convert result to 2x2 matrix
        result = np.array([
            [result_bytes[0], result_bytes[1]],
            [result_bytes[2], result_bytes[3]]
        ])
        
        return result
    
    def close(self):
        """Close the SPI connection"""
        self.spi_controller.terminate()

# Example usage
if __name__ == "__main__":
    try:
        # Print instructions
        print("=" * 50)
        print("ARTY A7 QSPI Matrix Multiplier")
        print("=" * 50)
        print("Make sure your ARTY A7 is connected and programmed with the matrix multiplier design.")
        print("QSPI connections should be wired to one of the PMOD connectors (JA or JB).")
        print("Pin mapping:")
        print("  - QSPI Data[0-3]: Connect to lower 4 pins of the PMOD")
        print("  - QSPI CS: Connect to pin 5")
        print("  - QSPI CLK: Connect to pin 6")
        print("=" * 50)
        
        # Optional: Let user select FTDI URL if automatic detection fails
        try_custom = input("Use automatic device detection? [Y/n]: ")
        
        ftdi_url = None
        if try_custom.lower().startswith('n'):
            ftdi_url = input("Enter FTDI URL (e.g., 'ftdi://ftdi:2232h/2'): ")
        
        # Initialize the controller
        matrix_mult = QSPIMatrixMultiplier(ftdi_url)
        
        # Create test matrices
        A = np.array([[1, 2], [3, 4]])
        B = np.array([[5, 6], [7, 8]])
        
        print("\nMatrix A:")
        print(A)
        
        print("\nMatrix B:")
        print(B)
        
        # Expected result: [[19, 22], [43, 50]]
        
        # Perform multiplication
        result = matrix_mult.multiply_matrices(A, B)
        
        print("\nResult (A × B):")
        print(result)
        
        # Verify with numpy's matrix multiplication
        expected = A @ B
        print("\nExpected result:")
        print(expected)
        
        # Check if result matches
        if np.array_equal(result, expected):
            print("\nSuccess! FPGA result matches expected calculation.")
        else:
            print("\nWarning: Results don't match expected calculation.")
            
    except Exception as e:
        print(f"\nError: {e}")
        
    finally:
        # Clean up
        if 'matrix_mult' in locals():
            matrix_mult.close()
        
        print("\nPress Enter to exit...")
        input()