#!/bin/sh

set -e

ROOT="$(pwd)/.."

rm -rf build
mkdir -p build
cd build

ghdl -a --std=08 --work=util "$ROOT/src/util/huffman_pkg.vhd"
ghdl -a --std=08 --work=util "$ROOT/src/util/math_pkg.vhd"
ghdl -a --std=08 --work=util "$ROOT/src/util/png_pkg.vhd"
ghdl -a --std=08 --work=png_lib "$ROOT/src/bram.vhd"
ghdl -a --std=08 --work=png_lib "$ROOT/src/lzss.vhd"
ghdl -a --std=08 --work=png_lib "$ROOT/src/adler32.vhd"
ghdl -a --std=08 --work=png_lib "$ROOT/src/crc32.vhd"
ghdl -a --std=08 --work=png_lib "$ROOT/src/huffman.vhd"
ghdl -a --std=08 --work=png_lib "$ROOT/src/deflate.vhd"
ghdl -a --std=08 --work=png_lib "$ROOT/src/zlib.vhd"
ghdl -a --std=08 --work=png_lib "$ROOT/src/row_filter.vhd"
ghdl -a --std=08 --work=png_lib "$ROOT/src/png_encoder.vhd"
# ghdl --synth --std=08 --work=png_lib png_encoder
yosys -m ghdl -p 'ghdl --std=08 --work=png_lib --no-formal png_encoder; synth_ice40 -json png_encoder.json'
# nextpnr-ice40 --hx1k --package tq144 --json png_encoder.json --asc png_encoder.asc
# nextpnr-ice40 --hx8k --package cm81 --json png_encoder.json --asc png_encoder.asc
# icepack png_encoder.asc png_encoder.bin
# iceprog png_encoder.bin
