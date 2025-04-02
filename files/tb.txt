`default_nettype none
`timescale 1ns / 1ps

module tb ();

  // Dump the signals to a VCD file for viewing with gtkwave
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end

  // System signals
  reg clk;
  reg rst_n;
  
  // UART signals - these are the ones your test.py needs to access
  reg uart_rx;        // From PC to FPGA
  wire uart_tx;       // From FPGA to PC
  
  // Instantiate the full system (uart + matrix mult)
  top_arty_matrix_mult dut (
    .clk(clk),
    .rst_n(rst_n),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx)
  );

endmodule