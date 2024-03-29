#!/usr/bin/env python3

"""Run all unit tests, contained by the subfolders."""

from glob import glob
import importlib.util
import os
import resource

import random
from vunit import VUnit


def create_test_suites(prj):
    """Collect the test and run them."""
    root = os.path.dirname(__file__)

    testbenches = glob(os.path.join(root, "*", "tb_*.vhd"))
    sim_lib = prj.add_library("sim")
    sim_lib.add_source_files("vunit_common_pkg.vhd")
    sim_lib.add_source_files(testbenches)

    util_lib = prj.add_library("util")
    util_lib.add_source_files("../src/util/*.vhd")
    png_lib = prj.add_library("png_lib")
    png_lib.add_source_files("../src/*.vhd")

    # TODO: add code coverage

    run_scripts = glob(os.path.join(root, "*", "run.py"))
    for run_script in run_scripts:
        spec = importlib.util.spec_from_file_location("run", run_script)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        mod.create_test_suite(sim_lib)

    # avoid error "type of a shared variable must be a protected type"
    prj.set_compile_option("ghdl.a_flags", ["-frelaxed"])
    prj.set_sim_option("ghdl.elab_flags", ["-frelaxed"])


if __name__ == "__main__":
    random.seed(42)

    os.environ["VUNIT_SIMULATOR"] = "ghdl"

    # Modify the stack size limit in order to avoid a stack overflow when
    # loading large arrays. See also: https://github.com/VUnit/vunit/issues/652
    resource.setrlimit(resource.RLIMIT_STACK, (resource.RLIM_INFINITY,
                                               resource.RLIM_INFINITY))

    PRJ = VUnit.from_argv(compile_builtins=False)
    PRJ.add_vhdl_builtins()
    create_test_suites(PRJ)
    PRJ.main()
