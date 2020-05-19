#!/usr/bin/env python3

"""Run all unit tests, contained by the subfolders."""

from glob import glob
import imp
import os
import resource

from vunit import VUnit


def create_test_suites(prj):
    """Collect the test and run them."""
    root = os.path.dirname(__file__)

    prj.add_array_util()
    sim_lib = prj.add_library("sim", allow_duplicate=True)
    sim_lib.add_source_files("vunit_common_pkg.vhd")
    util_lib = prj.add_library("util", allow_duplicate=True)
    util_lib.add_source_files("../src/util/*.vhd")
    png_lib = prj.add_library("png_lib", allow_duplicate=True)
    png_lib.add_source_files("../src/*.vhd")

    # TODO: add code coverage

    run_scripts = glob(os.path.join(root, "*", "run.py"))
    for run_script in run_scripts:
        mod = imp.find_module("run", [os.path.dirname(run_script)])
        run = imp.load_module("run", *mod)
        run.create_test_suite(prj)
        mod[0].close()

    # avoid error "type of a shared variable must be a protected type"
    prj.set_compile_option("ghdl.a_flags", ["-frelaxed"])
    prj.set_sim_option("ghdl.elab_flags", ["-frelaxed"])


if __name__ == "__main__":
    os.environ["VUNIT_SIMULATOR"] = "ghdl"

    # Modify the stack size limit in order to avoid a stack overflow when
    # loading large arrays. See also: https://github.com/VUnit/vunit/issues/652
    resource.setrlimit(resource.RLIMIT_STACK, (resource.RLIM_INFINITY,
                                               resource.RLIM_INFINITY))

    PRJ = VUnit.from_argv()
    create_test_suites(PRJ)
    PRJ.main()
