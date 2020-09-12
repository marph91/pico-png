"""Test cases for the png_encoder module."""

import dataclasses
import io
import itertools
import os
from os.path import join, dirname
import zlib

import pytest

from cocotb_test.simulator import run
from cocotb_test.simulator import Ghdl


# https://stackoverflow.com/questions/44624407/how-to-reduce-log-line-size-in-cocotb
os.environ["COCOTB_REDUCED_LOG_FMT"] = "1"


class GhdlCustom(Ghdl):
    def __init__(self, file_specific_compile_args=None, **kwargs):
        super().__init__(**kwargs)
        self.file_specific_compile_args = file_specific_compile_args
        self.sim_file = os.path.join(self.sim_dir, self.toplevel + ".o")

    def build_command(self):
        cmd = []

        if self.outdated(self.sim_file, self.verilog_sources + self.vhdl_sources) or self.force_compile:
            for source_file, compile_args in zip(self.vhdl_sources, self.file_specific_compile_args):
                cmd.append(["ghdl", "-i"] + self.compile_args + [compile_args, source_file])

            cmd_elaborate = ["ghdl", "-m"] + self.compile_args + [compile_args, self.toplevel]  # TODO: compile_args only for toplevel
            cmd.append(cmd_elaborate)

        cmd_run = [
            "ghdl",
            "-r",
            self.toplevel,
            "--vpi=" + os.path.join(self.lib_dir, "libcocotbvpi_ghdl." + self.lib_ext),
        ] + self.simulation_args

        if not self.compile_only:
            cmd.append(cmd_run)

        return cmd


@dataclasses.dataclass
class Testcase:
    name: str
    width: int
    height: int
    color_type: int
    block_type: int
    row_filter: int

    @property
    def id_(self) -> str:
        return (f"{self.name}_{self.width}x{self.height}_"
                f"row_filter_{self.row_filter}_color_{self.color_type}_"
                f"btype_{self.block_type}")


def generate_testcases():
    testcases = []
    for name, img_size, color_type, block_type, row_filter in itertools.product(
            ("increment", "ones", "random"), ((4, 4), (12, 12), (60, 80)),
            (0, 2, 4, 6), (0, 1), (0, 1)):
        if row_filter != 0 and img_size != (12, 12):
            continue  # skip some tests to reduce execution time

        testcases.extend([
            Testcase(name, *img_size, color_type, block_type, row_filter),
        ])

    # regression
    testcases.extend([
        Testcase("ones", 3, 5, 2, 1, 0),
        Testcase("ones", 5, 3, 4, 1, 0),
    ])

    # comparison to https://ipbloq.files.wordpress.com/2017/09/ipb-png-e-pb.pdf
    testcases.append(Testcase("ones", 800, 480, 2, 1, 0))
    return testcases


@pytest.mark.parametrize("case", generate_testcases())
def test_png_encoder(case):
    generics = {
        # "id": case.id_,
        "C_IMG_WIDTH": case.width,
        "C_IMG_HEIGHT": case.height,
        "C_IMG_BIT_DEPTH": 8,
        "C_COLOR_TYPE": case.color_type,
        "C_INPUT_BUFFER_SIZE": 12,
        "C_SEARCH_BUFFER_SIZE": 12,
        "C_BTYPE": case.block_type,
        "C_ROW_FILTER_TYPE": case.row_filter,
    }
    simulation_args = [f"-g{name}={value}" for name, value in generics.items()]
    # simulation_args.append(f"--wave=../test_{case.id_}.ghw")

    src_path = "/home/martin/dev/vhdl/pico-png/src/"
    GhdlCustom(
        vhdl_sources=[
            src_path + "util/math_pkg.vhd",
            src_path + "util/png_pkg.vhd",
            src_path + "lz77.vhd",
            src_path + "lzss.vhd",
            src_path + "adler32.vhd",
            src_path + "crc32.vhd",
            src_path + "huffman.vhd",
            src_path + "deflate.vhd",
            src_path + "zlib.vhd",
            src_path + "row_filter.vhd",
            src_path + "png_encoder.vhd",
        ], # sources
        toplevel="png_encoder",            # top level HDL
        module="test_png_encoder_cocotb",        # name of cocotb test module
        compile_args=["--std=08"],
        file_specific_compile_args=[
            "--work=util",
            "--work=util",
            "--work=png_lib",
            "--work=png_lib",
            "--work=png_lib",
            "--work=png_lib",
            "--work=png_lib",
            "--work=png_lib",
            "--work=png_lib",
            "--work=png_lib",
            "--work=png_lib",
        ],
        simulation_args=simulation_args,
        # testcase=case.name,
    ).run()
