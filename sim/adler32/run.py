"""Test cases for the adler32 implementation."""

from collections import namedtuple
import os
from os.path import join, dirname
from random import randint
import zlib

from vunit import VUnit


def to_signed(int_):
    """Convert a signed 32 bit number to an unsigned 32 bit number.
    Useful for VUnit, since the "integer_array_t" needs signed int.
    """
    if int_ > 2**31-1:
        return (2**32 - int_) * (-1)
    return int_


def generate_data(root, name, input_data):
    filename = join(root, "gen", "input_%s.csv" % name)
    input_data_preprocessed = [int.from_bytes(datum, "big")
                               for datum in input_data]
    input_data_preprocessed = map(to_signed, input_data_preprocessed)
    input_data_preprocessed = map(str, input_data_preprocessed)
    with open(filename, "w") as infile:
        infile.write(", ".join(input_data_preprocessed))

    output_data = to_signed(zlib.adler32(b"".join(input_data)))

    filename = join(root, "gen", "output_%s.csv" % name)
    with open(filename, "w") as outfile:
        outfile.write(str(output_data))


def create_test_suite(ui):
    root = dirname(__file__)
    os.makedirs(join(root, "gen"), exist_ok=True)

    ui.add_array_util()
    unittest = ui.add_library("unittest", allow_duplicate=True)
    unittest.add_source_files(join(root, "tb_adler32.vhd"))
    tb_adler32 = unittest.entity("tb_adler32")

    Case = namedtuple("Case", ["name", "data_in"])
    testcases = [
        Case("24_bit", [b"\x61\x62\x63"]),
        Case("8_bit_random", [randint(0, 255).to_bytes(1, "big")]),
        Case("32_bit_random", [randint(0, 2 ** 31 - 1).to_bytes(4, "big")]),
        Case("IEND", [b"\x49\x45\x4e\x44"]),
        Case("8_bit_serial",
             [randint(0, 255).to_bytes(1, "big") for _ in range(4)]),
        Case("32_bit_serial",
             [randint(0, 2 ** 31 - 1).to_bytes(4, "big") for _ in range(4)]),
        Case("trigger_overflow", [b"FF" for _ in range(100)]),
    ]

    for case in testcases:
        # TODO: sequential processing
        generics = {
            "id": case.name,
            "C_INPUT_BITWIDTH": len(case.data_in[0]) * 8
        }
        tb_adler32.add_config(
            name=case.name, generics=generics,
            pre_config=generate_data(root, case.name, case.data_in))


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
