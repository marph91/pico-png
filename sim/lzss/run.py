"""Test cases for the lzss implementation."""

from dataclasses import dataclass
from math import ceil, log2
import os
from os.path import join, dirname
from typing import List, Union

from vunit import VUnit


def create_stimuli(root, case):
    filename = join(root, "gen", f"input_{case.name}.csv")
    with open(filename, "w") as infile:
        infile.write(", ".join(map(str, case.data_in)))

    filename = join(root, "gen", f"output_{case.name}.csv")
    with open(filename, "w") as outfile:
        outfile.write(", ".join(map(str, case.data_out_int)))
    return True


def lb(size):
    return ceil(log2(size))


@dataclass
class Match:
    offset: int
    length: int


@dataclass
class Literal:
    value: int


@dataclass
class Case:
    name: str
    input_buffer_size: int
    search_buffer_size: int
    data_in: List[int]
    data_out: List[Union[Literal, Match]]

    @property
    def data_out_int(self) -> List[int]:
        buffer_size = lb(self.input_buffer_size) + lb(self.search_buffer_size)
        data_out_int = []
        for datum in self.data_out:
            if isinstance(datum, Literal):
                # match structure:
                # MSB: 1 (match), match offset, match length
                value_int = datum.value << max(0, buffer_size - 8)
            else:
                # non match structure:
                # MSB: 0 (non match), literal data, rest is ignored
                value_int = (
                    (1 << buffer_size) +
                    (datum.offset << lb(self.search_buffer_size)) +
                    datum.length
                )
            data_out_int.append(value_int)
        return data_out_int


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

    testcases = [
        # TODO: refactor: abstract literal and match
        Case("no_compression", 10, 12, [i for i in range(30)],
             [Literal(i) for i in range(30)]),
        # Case("rle", 5, 5, [0, 0, 0, 0, 1],
        #      [gen_literal(0, 5, 5),
        #       (1 << lb(5) + lb(5)) + (1 << lb(5)) + 3,
        #       gen_literal(1, 5, 5)
        #      ]),
        Case("rle_max_length", 20, 5, [0]*20 + [1],
             [Literal(0), Match(1, 5), Match(5, 5), Match(5, 5), Match(5, 4),
              Literal(1)]),
        Case("repeat", 11, 10, [0, 1, 2, 0, 1, 2, 0, 1, 2, 0],
             [Literal(0), Literal(1), Literal(2), Match(3, 7)]),
        Case("complex", 10, 12, complex_list,
             [Literal(0), Literal(1), Literal(2), Literal(3), Literal(4),
              Literal(5), Literal(6), Literal(2), Literal(7), Literal(5),
              Match(8, 7), Literal(encode_dict["n"]),
              Literal(encode_dict["d"]),
              Match(12, 7), Literal(encode_dict[" "]),
              Literal(encode_dict["h"]),
              Literal(encode_dict["e"]),
              Literal(encode_dict["r"]),
              Literal(encode_dict["u"]),
              Literal(encode_dict["m"]),
              Literal(encode_dict["."]),
             ]),
    ]

    for case in testcases:
        generics = {
            "id": case.name,
            "C_INPUT_BUFFER_SIZE": case.input_buffer_size,
            "C_SEARCH_BUFFER_SIZE": case.search_buffer_size,
            "C_MIN_MATCH_LENGTH": 3,
        }
        tb_lzss.add_config(
            name=case.name, generics=generics,
            pre_config=lambda: create_stimuli(root, case))
