import io
import os
from os.path import join, dirname
from random import randint
from typing import List
import zlib

from PIL import Image

import cocotb
from cocotb.clock import Clock
from cocotb.decorators import coroutine
from cocotb.triggers import Timer, RisingEdge
from cocotb.monitors import Monitor
from cocotb.regression import TestFactory
from cocotb.scoreboard import Scoreboard
from cocotb.result import TestFailure, TestSuccess


def apply_filter(data: bytes) -> List[int]:
    """Reconstruct original data from filter type and filtered data."""
    filter_type = data[0]
    if filter_type == 0:
        # no filter
        return list(data[1:])
    elif filter_type == 1:
        original_data = []
        last_value = 0
        for datum in data[1:]:
            reconstructed_value = (datum + last_value) % 256
            original_data.append(reconstructed_value)
            last_value = reconstructed_value
        return original_data
    else:
        raise ValueError(f"Filter type {data[0]} not implemented.")


def assemble_png(output_data, name):
    # Switch header and data. Header is sent later, because the chunk
    # length has to be specified there.
    # Strip the last three bytes of the header. They are only padded.
    png_bytes = bytearray(output_data)
    png_bytes = png_bytes[-44:-3] + png_bytes[:-44]
    # with open(f"../test_img_{name}.png", "wb") as outfile:
    #     outfile.write(png_bytes)
    return png_bytes


def check_png(input_data, png_bytes, width, depth):
    # verify the image data with pillow
    png_img = Image.open(io.BytesIO(png_bytes))
    png_img.verify()

    # verify the IDAT data with zlib
    idat_index = png_bytes.index(b"IDAT")
    idat_length = int.from_bytes(png_bytes[idat_index - 4:idat_index], "big")
    idat_data = png_bytes[idat_index + 4:idat_index + 4 + idat_length]

    print("debug info:")
    print([hex(d) for d in idat_data])
    print(["".join(reversed(bin(d)[2:].zfill(8))) for d in idat_data])
    print("infgen command:\n",
          "echo -n -e",
          "".join(["\\\\x" + hex(d)[2:].zfill(2) for d in idat_data]),
          "| ./infgen")

    decoded_data = zlib.decompress(idat_data)
    # split the output into scanlines
    scanlines = [decoded_data[x:x + width*depth + 1]
                 for x in range(0, len(decoded_data), width*depth + 1)]
    # apply filter types to each scanline and strip the filter byte
    # this is the preparation for comparison with the original input data
    reconstructed_data = []
    for line in scanlines:
        reconstructed_data.extend(apply_filter(line))

    print("input data:", input_data)
    print("reconstructed data:", reconstructed_data)
    assert input_data == reconstructed_data


def generate_input_data(height, width, depth):
    range_ = range(height * width * depth)
    # set via testcase member of the simulator
    input_type = os.environ.get("TESTCASE")
    if input_type == "increment":
        return [i % 256 for i in range_]
    elif input_type == "ones":
        return [1 for _ in range_]
    elif input_type == "ones":
        return [randint(0, 255) for _ in range_]

    return [1 for _ in range_]
    # raise ValueError("Unknown input type: ", input_type) # TODO: fix

@cocotb.coroutine
def clock_gen(signal):
    """Generate the clock signal."""
    while True:
        signal <= 0
        yield Timer(5000)  # ps
        signal <= 1
        yield Timer(5000)  # ps


class OutputMonitor(Monitor):
    """Observes single input or output of DUT."""
    def __init__(self, name, signal, valid, clock, callback=None, event=None):
        self.name = name
        self.signal = signal
        self.valid = valid
        self.clock = clock
        self.output = []
        Monitor.__init__(self, callback, event)

    @coroutine
    def _monitor_recv(self):
        clkedge = RisingEdge(self.clock)

        while True:
            # Capture signal at rising edge of clock
            yield clkedge
            if self.valid.value.integer == 1:
                vec = self.signal.value.integer
                print(self.signal)
                print(vec)
                self.output.append(vec)


def color_type_to_depth(color_type) -> int:
    if color_type == 0:
        return 1  # gray
    elif color_type == 2:
        return 3  # RGB
    elif color_type == 3:
        return 1  # palette (TODO: is this correct?)
    elif color_type == 4:
        return 2  # gray with alpha
    elif color_type == 6:
        return 4  # RGB with alpha
    raise ValueError(f"invalid color type {color_type}")

@cocotb.coroutine
def run_test(dut):
    """Setup testbench and run a test."""
    cocotb.fork(clock_gen(dut.isl_clk))

    byte_depth = color_type_to_depth(dut.C_COLOR_TYPE.value.integer)
    input_data = generate_input_data(
        dut.C_IMG_HEIGHT.value.integer,
        dut.C_IMG_WIDTH.value.integer,
        byte_depth)
    output_mon = OutputMonitor("output", dut.oslv_data, dut.osl_valid, dut.isl_clk)

    # init
    dut.isl_start <= 0
    dut.isl_valid <= 0
    dut.islv_data <= 0
    
    yield RisingEdge(dut.isl_clk)
    dut.isl_start <= 1
    yield RisingEdge(dut.isl_clk)
    dut.isl_start <= 0

    for input_value in input_data:
        # print(input_value)
        while dut.osl_rdy.value.integer != 1:
            yield RisingEdge(dut.isl_clk)
        dut.isl_valid <= 1
        dut.islv_data <= input_value
        yield RisingEdge(dut.isl_clk)
        dut.isl_valid <= 0
        yield RisingEdge(dut.isl_clk)

    while dut.osl_finish.value.integer != 1:
        yield RisingEdge(dut.isl_clk)

    png_bytes = assemble_png(output_mon.output, "tmp")
    check_png(input_data, png_bytes, dut.C_IMG_WIDTH.value.integer, byte_depth)

factory = TestFactory(run_test)
factory.generate_tests()
