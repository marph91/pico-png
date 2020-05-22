"""Test cases for the lz77 implementation."""

from collections import namedtuple
import os
from os.path import join, dirname
from random import randint

from vunit import VUnit


def create_stimuli(root, name, input_data, output_data):
    # TODO: implement full lz77 in python
    filename = join(root, "gen", "input_%s.csv" % name)
    with open(filename, "w") as infile:
        infile.write(", ".join(map(str, input_data)))

    filename = join(root, "gen", "output_%s.csv" % name)
    with open(filename, "w") as outfile:
        outfile.write(", ".join(map(str, output_data)))


def create_test_suite(tb_lib):
    root = dirname(__file__)
    os.makedirs(join(root, "gen"), exist_ok=True)

    tb_lz77 = tb_lib.entity("tb_lz77")

    # https://de.wikipedia.org/wiki/LZ77
    # https://de.wikibooks.org/wiki/Datenkompression:_Verlustfreie_Verfahren:_W%C3%B6rterbuchbasierte_Verfahren:_LZ77

    complex_sentence = "In Ulm, um Ulm, und um Ulm herum."
    encode_dict = {"I": 0, "n": 1, " ": 2, "U": 3, "l": 4, "m": 5, ",": 6,
                   "u": 7, "d": 8, "h": 9, "e": 10, "r": 11, ".": 12}
    complex_list = [encode_dict[letter] for letter in complex_sentence]

    Case = namedtuple("Case", ["name", "input_buffer_size",
                               "search_buffer_size", "data_in", "data_out"])
    testcases = (
        Case("no_compression", 10, 12, [i for i in range(30)],
             [i for i in range(30)]),
        Case("rle", 5, 5, [0, 0, 0, 0, 1], [0, (3 << 20) + (1 << 8) + 1]),
        Case("rle_max_length", 20, 5, [0]*20 + [1],
             [0, (15 << 20) + (1 << 8), (3 << 20) + (1 << 8) + 1]),
        Case("repeat", 11, 10, [0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 3],
             [0, 1, 2, (7 << 20) + (3 << 8) + 3]),
        Case("complex", 10, 12, complex_list,
             [0, 1, 2, 3, 4, 5, 6,
              (1 << 20) + (5 << 8) + encode_dict["u"],
              (1 << 20) + (4 << 8) + encode_dict[" "],
              (6 << 20) + (8 << 8) + encode_dict["n"],
              encode_dict["d"],
              (7 << 20) + (12 << 8) + encode_dict[" "],
              encode_dict["h"],
              encode_dict["e"],
              encode_dict["r"],
              (2 << 20) + (10 << 8) + encode_dict["."],
             ]),
        Case("complex2", 10, 12,
             [0, 0, 2, 0, 0, 2, 0, 1, 2, 0, 1, 0, 0, 0, 2, 3],
             [0,
              (1 << 20) + (1 << 8) + 2,
              (4 << 20) + (3 << 8) + 1,
              (3 << 20) + (3 << 8),
              (3 << 20) + (9 << 8) + 3,
             ]),
    )

    for case in testcases:
        generics = {
            "id": case.name,
            "C_INPUT_BUFFER_SIZE": case.input_buffer_size,
            "C_SEARCH_BUFFER_SIZE": case.search_buffer_size,
        }
        tb_lz77.add_config(
            name=case.name, generics=generics,
            pre_config=create_stimuli(root, case.name, case.data_in,
                                      case.data_out))
