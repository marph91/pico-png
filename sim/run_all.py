#!/usr/bin/env python3

"""Run all unit tests, contained by the subfolders."""

from glob import glob
import importlib.util
import os
from pathlib import Path
import random
import resource

import cocotb
from vunit import VUnit


def create_test_suites(prj):
    root = os.path.dirname(__file__)

    util_lib = prj.add_library("util")
    util_lib.add_source_files("../src/util/*.vhd")
    png_lib = prj.add_library("png_lib")
    png_lib.add_source_files("../src/*.vhd")

    run_scripts = glob(os.path.join(root, "*", "test_png_encoder.py"))
    for run_script in run_scripts:
        spec = importlib.util.spec_from_file_location("run", run_script)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        mod.create_test_suite(png_lib)

    ghdl_cocotb_lib = Path(os.path.dirname(cocotb.__file__)) / 'libs' / 'libcocotbvpi_ghdl.so'
    prj.set_sim_option("ghdl.sim_flags", [f"--vpi={ghdl_cocotb_lib}"])

    # TODO: how to set these for multiple tests?
    os.environ["MODULE"] = "test_png_encoder_cocotb"
    os.environ["PYTHONPATH"] = "png_encoder"

    # gprof2dot -f pstats test_profile.pstat | dot -Tpng -o output.png && display output.png
    # os.environ["COCOTB_ENABLE_PROFILING"] = "1"

    # https://stackoverflow.com/questions/15548023/clang-optimization-levels
    prj.add_compile_option("ghdl.a_flags", ["-O3"])


if __name__ == "__main__":
    random.seed(42)

    os.environ["VUNIT_SIMULATOR"] = "ghdl"

    PRJ = VUnit.from_argv()
    create_test_suites(PRJ)
    PRJ.main()
