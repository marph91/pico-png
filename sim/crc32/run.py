"""Test cases for the crc32 implementation."""

from collections import namedtuple
from functools import partial
import os
from os.path import join, dirname
from random import randint
import zlib

from vunit import VUnit


def to_signed(int_: int) -> int:
    """Convert a signed 32 bit number to an unsigned 32 bit number.
    Useful for VUnit, since the "integer_array_t" needs signed int.
    """
    if int_ > 2**31-1:
        return (2**32 - int_) * (-1)
    return int_


def generate_data(root, case):
    filename = join(root, "gen", f"input_{case.name}.csv")
    input_data_preprocessed = [int.from_bytes(datum, "big")
                               for datum in case.data_in]
    input_data_preprocessed = map(to_signed, input_data_preprocessed)
    input_data_preprocessed = map(str, input_data_preprocessed)
    with open(filename, "w") as infile:
        infile.write(", ".join(input_data_preprocessed))

    output_data = to_signed(zlib.crc32(b"".join(case.data_in)))

    filename = join(root, "gen", f"output_{case.name}.csv")
    with open(filename, "w") as outfile:
        outfile.write(str(output_data))
    return True


def create_test_suite(tb_lib):
    root = dirname(__file__)
    os.makedirs(join(root, "gen"), exist_ok=True)

    tb_crc32 = tb_lib.entity("tb_crc32")

    Case = namedtuple("Case", ["name", "data_in"])
    testcases = (
        # TODO: wordwidth, input width, datum count -> generate automatically
        # https://stackoverflow.com/a/45602238/7410886
        Case("word_24_bit_input_24_bit_datums_1", [b"\x61\x62\x63"]),
        Case("word_24_bit_input_8_bit_datums_3", [b"\x61", b"\x62", b"\x63"]),
        Case("word_8_bit_input_8_bit_datums_1",
             [randint(0, 255).to_bytes(1, "big")]),
        Case("word_8_bit_input_8_bit_datums_4",
             [randint(0, 255).to_bytes(1, "big") for _ in range(4)]),
        Case("word_32_bit_input_32_bit_datums_1",
             [randint(0, 2 ** 32 - 1).to_bytes(4, "big")]),
        Case("word_32_bit_input_32_bit_datums_100",
             [randint(0, 2 ** 32 - 1).to_bytes(4, "big") for _ in range(100)]),
        Case("word_32_bit_input_32_bit_datums_1_IEND", [b"\x49\x45\x4e\x44"]),
        Case("word_32_bit_input_8_bit_datums_4_IEND",
             [b"\x49", b"\x45", b"\x4e", b"\x44"]),
        Case("word_64_bit_input_64_bit_datums_1",
             [b"".join([randint(0, 2 ** 64 - 1).to_bytes(8, "big")])]),
    )

    for case in testcases:
        stimuli = []
        for datum in case.data_in:
            for byte_ in datum[::-1]:
                stimuli.append((bin(byte_)[2:].zfill(8))[::-1])
            stimuli.append(", ")

        stimuli = ("".join(stimuli))[:-2]
        reference = to_signed(zlib.crc32(b"".join(case.data_in)))
        generics = {
            "id": case.name,
            "C_INPUT_BITWIDTH": len(case.data_in[0]) * 8,
            "input_data": stimuli,
            "reference_data": reference,
        }
        tb_crc32.add_config(
            name=case.name, generics=generics,
            pre_config=partial(generate_data, root, case))
