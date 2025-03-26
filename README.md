![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Tiny Tapeout Verilog Project Template

- [Read the documentation for project](docs/info.md)

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip.

To learn more and get started, visit https://tinytapeout.com.

## Set up your Verilog project

1. Add your Verilog files to the `src` folder.
2. Edit the [info.yaml](info.yaml) and update information about your project, paying special attention to the `source_files` and `top_module` properties. If you are upgrading an existing Tiny Tapeout project, check out our [online info.yaml migration tool](https://tinytapeout.github.io/tt-yaml-upgrade-tool/).
3. Edit [docs/info.md](docs/info.md) and add a description of your project.
4. Adapt the testbench to your design. See [test/README.md](test/README.md) for more information.

The GitHub action will automatically build the ASIC files using [OpenLane](https://www.zerotoasiccourse.com/terminology/openlane/).

## Enable GitHub actions to build the results page

- [Enabling GitHub Pages](https://tinytapeout.com/faq/#my-github-action-is-failing-on-the-pages-part)

## Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Learn how semiconductors work](https://tinytapeout.com/siliwiz/)
- [Join the community](https://tinytapeout.com/discord)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)

## What next?

- [Submit your design to the next shuttle](https://app.tinytapeout.com/).
- Edit [this README](README.md) and explain your design, how it works, and how to test it.
- Share your project on your social network of choice:
  - LinkedIn [#tinytapeout](https://www.linkedin.com/search/results/content/?keywords=%23tinytapeout) [@TinyTapeout](https://www.linkedin.com/company/100708654/)
  - Mastodon [#tinytapeout](https://chaos.social/tags/tinytapeout) [@matthewvenn](https://chaos.social/@matthewvenn)
  - X (formerly Twitter) [#tinytapeout](https://twitter.com/hashtag/tinytapeout) [@tinytapeout](https://twitter.com/tinytapeout)

### Quick Start Journal (for agneya)
- remember to `wsl --shutdown`
- to generate a .vcd, instantiate the virtual python environment `source venv/bin/activate` IN WSL and run `make -B` in the test folder

- if starting a new project, open WSL, run `python -m venv venv` in the test folder. Then, `source venv/bin/activate` to start the virtual environment. Then, `pip install -r requirements.txt` to install the necessary packages.

- start wsl
- python3 -m venv venv (create virtual environment. MUST BE MADE IN WSL)
- source venv/bin/activate (activate virtual environment)
- pip install -r requirements.txt (install necessary packages)
- change the module name in tb.v
- make -B (run the testbench)

- spi is main project, template is the buildable project

- uart_to_spi.v is the module file i put into vivado

- below code im supposed to put into my project.v file?


```
uart_to_spi uart (
        .clk(clock),
        .resetn(porb_h),        // "_h" is only valid for FPGA!

        .ser_tx(ser_tx_out),
        .ser_rx(ser_rx_in),

        .spi_sck(mprj_io_in[4]),
        .spi_csb(mprj_io_in[3]),
        .spi_sdo(mprj_io_out[1]),
        .spi_sdi(mprj_io_in[2]),

        .mgmt_uart_rx(mprj_io_in[5]),
        .mgmt_uart_tx(mprj_io_out[6]),

        .mgmt_uart_enabled(uart_enabled)
  );
```

### OPERATION SERIAL TO USB TO UART TO SPI 
- Top arty file recieves data from the computer via USB, sends it to the UART module, which sends it to the SPI module, which sends it to the FPGA. The FPGA then sends the data to the SPI module, which sends it to the UART module, which sends it to the Top arty file, which sends it to the computer via USB.
- to run the `interface_fpga.py` file, i just set my python interpreter to the pythonw.exe file in the scripts folder. i have no idea what this does. but somehow it worked. 