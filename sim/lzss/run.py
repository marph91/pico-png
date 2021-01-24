"""Test cases for the lzss implementation."""

from collections import namedtuple
from math import ceil, log2
import os
from os.path import join, dirname

from vunit import VUnit


def create_stimuli(root, name, input_data, output_data):
    # TODO: implement full lzss in python
    filename = join(root, "gen", "input_%s.csv" % name)
    with open(filename, "w") as infile:
        infile.write(", ".join(map(str, input_data)))

    filename = join(root, "gen", "output_%s.csv" % name)
    with open(filename, "w") as outfile:
        outfile.write(", ".join(map(str, output_data)))


def lb(size):
    return ceil(log2(size))


def gen_literal(literal_value, input_buffer_size, search_buffer_size):
    return literal_value << max(0, lb(input_buffer_size) + lb(search_buffer_size) - 8)


def create_test_suite(tb_lib):
    root = dirname(__file__)
    os.makedirs(join(root, "gen"), exist_ok=True)

    tb_lzss = tb_lib.entity("tb_lzss")

    # https://de.wikibooks.org/wiki/Datenkompression:_Verlustfreie_Verfahren:_W%C3%B6rterbuchbasierte_Verfahren:_LZSS
    # J. Storer, T.Szymanski. Data Compression via Textual Substitution.
    complex_sentence = "In Ulm, um Ulm, und um Ulm herum."
    encode_dict = {"I": 0, "n": 1, " ": 2, "U": 3, "l": 4, "m": 5, ",": 6,
                   "u": 7, "d": 8, "h": 9, "e": 10, "r": 11, ".": 12}
    complex_list = [encode_dict[letter] for letter in complex_sentence]

    # structure of data_out in case of match:
    # MSB: 1 (match), 12 bit: match distance, 4 bit: match length
    # structure of data_out in case of non match:
    # MSB: 0 (non match), 8 bit literal data, 8 bit ignored
    Case = namedtuple("Case", ["name", "input_buffer_size",
                               "search_buffer_size", "data_in", "data_out"])
    testcases = [
        # TODO: refactor: abstract literal and match
        Case("no_compression", 10, 12, [i for i in range(30)],
             [gen_literal(i, 10, 12) for i in range(30)]),
        # Case("rle", 5, 5, [0, 0, 0, 0, 1],
        #      [gen_literal(0, 5, 5),
        #       (1 << lb(5) + lb(5)) + (1 << lb(5)) + 3,
        #       gen_literal(1, 5, 5)
        #      ]),
        Case("rle_max_length", 20, 5, [0]*20 + [1],
             [gen_literal(0, 20, 5),
              (1 << lb(20) + lb(5)) + (1 << lb(5)) + 5,
              (1 << lb(20) + lb(5)) + (5 << lb(5)) + 5,
              (1 << lb(20) + lb(5)) + (5 << lb(5)) + 5,
              (1 << lb(20) + lb(5)) + (5 << lb(5)) + 4,
              gen_literal(1, 20, 5),
             ]),
        Case("repeat", 11, 10, [0, 1, 2, 0, 1, 2, 0, 1, 2, 0],
             [gen_literal(0, 11, 10),
              gen_literal(1, 11, 10),
              gen_literal(2, 11, 10),
              (1 << lb(11) + lb(10)) + (3 << lb(10)) + 7
             ]),
        Case("complex", 10, 12, complex_list,
             [gen_literal(0, 10, 12),
              gen_literal(1, 10, 12),
              gen_literal(2, 10, 12),
              gen_literal(3, 10, 12),
              gen_literal(4, 10, 12),
              gen_literal(5, 10, 12),
              gen_literal(6, 10, 12),
              gen_literal(2, 10, 12),
              gen_literal(7, 10, 12),
              gen_literal(5, 10, 12),
              (1 << lb(10) + lb(12)) + (8 << lb(12)) + 7,
              gen_literal(encode_dict["n"], 10, 12),
              gen_literal(encode_dict["d"], 10, 12),
              (1 << lb(10) + lb(12)) + (12 << lb(12)) + 7,
              gen_literal(encode_dict[" "], 10, 12),
              gen_literal(encode_dict["h"], 10, 12),
              gen_literal(encode_dict["e"], 10, 12),
              gen_literal(encode_dict["r"], 10, 12),
              gen_literal(encode_dict["u"], 10, 12),
              gen_literal(encode_dict["m"], 10, 12),
              gen_literal(encode_dict["."], 10, 12),
             ]),
    ]

    for case in testcases:
        print(case)
        generics = {
            "id": case.name,
            "C_INPUT_BUFFER_SIZE": case.input_buffer_size,
            "C_SEARCH_BUFFER_SIZE": case.search_buffer_size,
            "C_MIN_MATCH_LENGTH": 3,
        }
        tb_lzss.add_config(
            name=case.name, generics=generics,
            pre_config=create_stimuli(root, case.name, case.data_in,
                                      case.data_out))
