"""Test cases for the lzss implementation."""

from dataclasses import dataclass
from functools import partial
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
    max_match_length: int
    data_in: List[int]
    data_out: List[Union[Literal, Match]]

    @property
    def data_out_int(self) -> List[int]:
        match_offset = lb(self.search_buffer_size)
        match_length = lb(
            min(self.input_buffer_size, self.max_match_length) + 1)
        # Assure a bitwidth of at least 8 bit. See also "lzss.vhd".
        if match_offset + match_length < 8:
            match_offset = 8 - match_length
        buffer_size = match_offset + match_length

        data_out_int = []
        for datum in self.data_out:
            if isinstance(datum, Literal):
                # non match structure:
                # MSB: 0 (non match), literal data, rest is ignored
                value_int = datum.value << (buffer_size - 8)
            else:
                # match structure:
                # MSB: 1 (match), match offset, match length
                value_int = (
                    (1 << buffer_size) +
                    (datum.offset << match_length) +
                    datum.length
                )
            data_out_int.append(value_int)
        return data_out_int


def create_test_suite(tb_lib):
    root = dirname(__file__)
    os.makedirs(join(root, "gen"), exist_ok=True)

    tb_lzss = tb_lib.entity("tb_lzss")

    # TODO: Add test cases for max_match_length < input_buffer_size
    max_match_length = 32

    # https://de.wikibooks.org/wiki/Datenkompression:_Verlustfreie_Verfahren:_W%C3%B6rterbuchbasierte_Verfahren:_LZSS
    # J. Storer, T.Szymanski. Data Compression via Textual Substitution.
    complex_sentence = "In Ulm, um Ulm, und um Ulm herum."
    encode_dict = {"I": 0, "n": 1, " ": 2, "U": 3, "l": 4, "m": 5, ",": 6,
                   "u": 7, "d": 8, "h": 9, "e": 10, "r": 11, ".": 12}
    complex_list = [encode_dict[letter] for letter in complex_sentence]

    testcases = [
        Case("no_compression", 10, 12, max_match_length,
             [i for i in range(30)], [Literal(i) for i in range(30)]),
        Case("rle", 5, 5, max_match_length, [0, 0, 0, 0, 1],
             [Literal(0), Match(1, 3), Literal(1)]),
        Case("max_match_length", 16, 5, 16, [0] * 17 + [1],
             [Literal(0), Match(1, 16), Literal(1)]),
        Case("max_match_offset", 4, 8, 4, [0, 1, 2, 3] * 3,
             [Literal(0), Literal(1), Literal(2), Literal(3),
              Match(4, 4), Match(8, 4)]),
        Case("repeat", 11, 10, max_match_length,
             [0, 1, 2, 0, 1, 2, 0, 1, 2, 0],
             [Literal(0), Literal(1), Literal(2), Match(3, 7)]),
        # Smoke test: Data doesn't matter. Just check if it compiles.
        Case("max_buffers", 258, 32768, max_match_length,
             [0], [Literal(0)]),
        Case("complex", 10, 12, max_match_length, complex_list,
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
        Case("match_at_max_size", 3, 3, 4, [0, 1, 2, 0, 1, 2],
             [Literal(0), Literal(1), Literal(2), Match(3, 3)]),
    ]

    for case in testcases:
        generics = {
            "id": case.name,
            "C_INPUT_BUFFER_SIZE": case.input_buffer_size,
            "C_SEARCH_BUFFER_SIZE": case.search_buffer_size,
            "C_MIN_MATCH_LENGTH": 3,
            "C_MAX_MATCH_LENGTH_USER": case.max_match_length,
        }
        tb_lzss.add_config(
            name=case.name, generics=generics,
            pre_config=partial(create_stimuli, root, case))
