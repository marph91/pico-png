# pico-png

[![testsuite](https://github.com/marph91/pico-png/workflows/tests/badge.svg)](https://github.com/marph91/pico-png/actions?query=workflow%3Atests)
[![synthesis](https://github.com/marph91/pico-png/workflows/synthesis/badge.svg)](https://github.com/marph91/pico-png/actions?query=workflow%3Asynthesis)

`pico-png` is a VHDL implementation of a PNG encoder, as specified in ISO/IEC 15948:2003, RFC1950 and RFC1951.

## Features

- Row filter types: no filter, subtraction filter
- Color types: gray, RGB, gray + alpha, RGBA
- Zlib compression: no compression, fixed huffman tables

For details about the configuration, see [here](doc/toplevel_interface.md).

## Architecture overview

![architecture_overview](doc/images/overview.svg)

## Tests

To run the testbench, simply execute `cd sim && ./run_all.py -p4`.
