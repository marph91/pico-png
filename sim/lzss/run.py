from collections import namedtuple
import os
from os.path import join, dirname
from random import randint

from vunit import VUnit


def create_stimuli(root, name, input_data, output_data):
    # TODO: implement full lzss in python
    filename = join(root, "gen", "input_%s.csv" % name)
    with open(filename, "w") as infile:
        infile.write(", ".join(map(str, input_data)))

    filename = join(root, "gen", "output_%s.csv" % name)
    with open(filename, "w") as outfile:
        outfile.write(", ".join(map(str, output_data)))


def create_test_suite(ui):
    root = dirname(__file__)
    os.makedirs(join(root, "gen"), exist_ok=True)

    ui.add_array_util()
    unittest = ui.add_library("unittest", allow_duplicate=True)
    unittest.add_source_files(join(root, "tb_lzss.vhd"))
    tb_lzss = unittest.entity("tb_lzss")

    # https://de.wikibooks.org/wiki/Datenkompression:_Verlustfreie_Verfahren:_W%C3%B6rterbuchbasierte_Verfahren:_LZSS
    # J. Storer, T.Szymanski. Data Compression via Textual Substitution.
    complex_sentence = "In Ulm, um Ulm, und um Ulm herum."
    encode_dict = {"I": 0, "n": 1, " ": 2, "U": 3, "l": 4, "m": 5, ",": 6,
                   "u": 7, "d": 8, "h": 9, "e": 10, "r": 11, ".": 12}
    complex_list = [encode_dict[letter] for letter in complex_sentence]

    Case = namedtuple("Case", ["name", "input_buffer_size",
                               "search_buffer_size", "data_in", "data_out"])
    testcases = [
        Case("no_compression", 10, 12, [i for i in range(30)],
             [(i << 8) for i in range(30)]),
        Case("rle", 5, 5, [0, 0, 0, 0, 1],
             [0, (1 << 16) + (1 << 4) + 3, 1 << 8]),
        Case("rle_max_length", 20, 5, [0]*20 + [1],
             [0, (1 << 16) + (1 << 4) + 15, (1 << 16) + (1 << 4) + 4, 1 << 8]),
        Case("repeat", 11, 10, [0, 1, 2, 0, 1, 2, 0, 1, 2, 0],
             [0 << 8, 1 << 8, 2 << 8, (1 << 16) + (3 << 4) + 7]),
        Case("complex", 10, 12, complex_list,
             [0, 1 << 8, 2 << 8, 3 << 8, 4 << 8, 5 << 8, 6 << 8, 2 << 8,
              7 << 8, 5 << 8,
              (1 << 16) + (8 << 4) + 7,
              encode_dict["n"] << 8,
              encode_dict["d"] << 8,
              (1 << 16) + (12 << 4) + 7,
              encode_dict[" "] << 8,
              encode_dict["h"] << 8,
              encode_dict["e"] << 8,
              encode_dict["r"] << 8,
              (1 << 16) + (10 << 4) + 2,
              encode_dict["."] << 8,
              ]),
    ]

    for case in testcases:
        generics = {
            "id": case.name,
            "C_INPUT_BUFFER_SIZE": case.input_buffer_size,
            "C_SEARCH_BUFFER_SIZE": case.search_buffer_size,    
        }
        tb_lzss.add_config(
            name=case.name, generics=generics,
            pre_config=create_stimuli(root, case.name, case.data_in,
                case.data_out))


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
