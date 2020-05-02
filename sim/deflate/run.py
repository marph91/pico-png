"""Test cases for the deflate module."""

from collections import namedtuple
import os
from os.path import join, dirname
import zlib

from vunit import VUnit


def deflate(data):
    """Deflate data."""
    compress = zlib.compressobj(
        0,
        zlib.DEFLATED,
        -zlib.MAX_WBITS,
        zlib.DEF_MEM_LEVEL,
        0
    )
    deflated = compress.compress(data)
    deflated += compress.flush()
    return deflated


def create_stimuli(root, name, input_data):
    filename = join(root, "gen", "input_%s.csv" % name)
    with open(filename, "w") as infile:
        infile.write(", ".join(map(str, input_data)))


def create_test_suite(ui):
    return  # TODO: add test
    root = dirname(__file__)
    os.makedirs(join(root, "gen"), exist_ok=True)

    ui.add_array_util()
    unittest = ui.add_library("unittest", allow_duplicate=True)
    unittest.add_source_files(join(root, "tb_deflate.vhd"))
    tb_deflate = unittest.entity("tb_deflate")

    Case = namedtuple("Case", ["name", "input_buffer_size",
                               "search_buffer_size", "data_in"])
    testcases = [
        Case("no_compression", 10, 12, [i for i in range(4)]),
    ]

    for case in testcases:
        # TODO: implement proper testbench
        input_bytes = bytearray(case.data_in)
        output_data = list(deflate(input_bytes))
        output_data_str = "".join([bin(d)[2:].zfill(8) for d in output_data])[5:][::-1]

        # print(deflate(input_bytes))
        # print(output_data)
        # print(output_data_str)

        generics = {"id": case.name,
                    "data_ref": output_data_str,
                    "C_INPUT_BUFFER_SIZE": case.input_buffer_size,
                    "C_SEARCH_BUFFER_SIZE": case.search_buffer_size,
                    "C_BTYPE": 0}
        tb_deflate.add_config(name=case.name, generics=generics,
                              pre_config=create_stimuli(root, case.name, case.data_in))


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
