import time
from pyftdi.spi import SpiController
import numpy as np

class QSPIMatrixMultiplier:
    def __init__(self, ftdi_url='ftdi://ftdi:2232h/1'):
        """Initialize the SPI controller for Arty S7 board connection.
        
        Args:
            ftdi_url: The FTDI device URL (may need adjustment for your specific board)
        """
        # Configure SPI controller
        self.spi_controller = SpiController()
        self.spi_controller.configure(ftdi_url)
        
        # Get SPI port 0 with 4-bit wide QSPI mode, 12MHz clock
        # CS active low (default), MSB first (default)
        self.spi = self.spi_controller.get_port(0, freq=12E6, mode=0)
        print("QSPI Matrix Multiplier connected")
    
    def multiply_matrices(self, matrix_a, matrix_b):
        """Multiply two 2x2 matrices using the FPGA implementation.
        
        Args:
            matrix_a: 2x2 NumPy array or list of lists
            matrix_b: 2x2 NumPy array or list of lists
            
        Returns:
            2x2 NumPy array with multiplication result
        """
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
        # First send matrix A, then matrix B in a single transaction
        write_data = a_bytes + b_bytes
        
        # We expect 4 bytes of result
        result_bytes = bytearray(4)
        
        # Write and read in a single transaction
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
    # Initialize the controller
    matrix_mult = QSPIMatrixMultiplier()
    
    try:
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
        
        print("\nResult (A x B):")
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
        print(f"Error: {e}")
        
    finally:
        # Clean up
        matrix_mult.close()