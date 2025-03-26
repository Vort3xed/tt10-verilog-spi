import time
import numpy as np

class UARTMatrixMultiplier:
    def __init__(self, com_port=None, baud_rate=96000):
        """Initialize the UART connection to the ARTY A7 board."""
        if com_port is None:
            # List available ports to help with selection
            import serial.tools.list_ports
            ports = list(serial.tools.list_ports.comports())
            print("Available COM ports:")
            for i, port in enumerate(ports):
                print(f"  {i}: {port.device} - {port.description}")
                
            if not ports:
                raise RuntimeError("No COM ports found. Is the ARTY A7 connected?")
                
            print("\nTip: Look for port described as 'USB Serial Port' or containing 'FTDI'")
            port_idx = int(input("Select port number: "))
            com_port = ports[port_idx].device
            
        print(f"Connecting to {com_port} at {baud_rate} baud...")
        self.ser = serial.Serial(com_port, baud_rate, timeout=1)
        print("Connected!")
        
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
        
        # Send data (A then B)
        write_data = a_bytes + b_bytes
        print(f"Sending data: {list(write_data)}")
        self.ser.write(write_data)
        
        # Read result (4 bytes)
        time.sleep(0.1)  # Give FPGA time to process
        result_bytes = self.ser.read(4)
        
        if len(result_bytes) < 4:
            print(f"Warning: Only received {len(result_bytes)} bytes, expected 4")
            # Pad with zeros if we didn't get enough data
            result_bytes = result_bytes + b'\x00' * (4 - len(result_bytes))
        
        # Convert result to 2x2 matrix
        result = np.array([
            [result_bytes[0], result_bytes[1]],
            [result_bytes[2], result_bytes[3]]
        ])
        
        return result
    
    def close(self):
        """Close the serial connection"""
        self.ser.close()
        print("Connection closed")

# Example usage
if __name__ == "__main__":
    try:
        # Initialize the UART connection
        matrix_mult = UARTMatrixMultiplier()
        
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