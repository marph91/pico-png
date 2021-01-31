"""Test cases for the png_encoder module."""

import dataclasses
from functools import partial
import io
import itertools
import os
from os.path import join, dirname
from random import randint
from typing import List
import zlib

from PIL import Image


def create_stimuli(root: str, case):
    # write out csv only for debugging purposes
    filename = join(root, "gen", f"input_{case.id_}.csv")
    with open(filename, "w") as infile:
        infile.write(", ".join(map(str, case.data_in)))

    filename = join(root, "gen", f"input_{case.id_}.raw")
    with open(filename, "wb") as infile:
        infile.write(bytes(case.data_in))  # only works for 8 bit values!
    return True


def apply_filter(data: bytes) -> List[int]:
    """Reconstruct original data from filter type and filtered data."""
    filter_type = data[0]
    if filter_type == 0:
        # no filter
        return list(data[1:])
    elif filter_type == 1:
        original_data = []
        last_value = 0
        for datum in data[1:]:
            reconstructed_value = (datum + last_value) % 256
            original_data.append(reconstructed_value)
            last_value = reconstructed_value
        return original_data
    else:
        raise ValueError(f"Filter type {data[0]} not implemented.")


# TODO: use getfullargspec() API to allow type annotations
def assemble_and_check_png(root, case):
    with open(join(root, "gen", f"png_{case.id_}.txt"), "r") as infile:
        binary_strings = infile.readlines()

    png_bytes = bytearray()
    for byte_str in binary_strings:
        assert len(byte_str) == 9, len(byte_str)  # 8 bit + newline
        png_bytes.append(int(byte_str, 2))

    # switch header and data. header is sent later, because the chunk
    # length has to be specified there.
    # strip the last three bytes of the header. they are only padded.
    png_bytes = png_bytes[-44:-3] + png_bytes[:-44]
    with open(join(root, "gen", f"test_img_{case.id_}.png"), "wb") as outfile:
        outfile.write(png_bytes)

    # verify the image data with pillow
    png_img = Image.open(io.BytesIO(png_bytes))
    png_img.verify()

    # verify the IDAT data with zlib
    idat_index = png_bytes.index(b"IDAT")
    idat_length = int.from_bytes(png_bytes[idat_index - 4:idat_index], "big")
    idat_data = png_bytes[idat_index + 4:idat_index + 4 + idat_length]

    print("debug info:")
    print([hex(d) for d in idat_data])
    print(["".join(reversed(bin(d)[2:].zfill(8))) for d in idat_data])
    print("infgen command:\n",
          "echo -n -e",
          "".join(["\\\\x" + hex(d)[2:].zfill(2) for d in idat_data]),
          "| ./infgen")

    decoded_data = zlib.decompress(idat_data)
    # apply filter types to compare with original data
    line_size = case.width * case.depth
    scanlines = [decoded_data[x:x + line_size + 1]
                 for x in range(0, len(decoded_data), line_size + 1)]
    reconstructed_data = []
    for line in scanlines:
        reconstructed_data.extend(apply_filter(line))

    input_data = bytearray(case.data_in)
    print("input data:", input_data, list(input_data))
    print("reconstructed data:", reconstructed_data)
    return list(input_data) == reconstructed_data


@dataclasses.dataclass
class Testcase:
    name: str
    width: int
    height: int
    color_type: int
    block_type: int
    row_filter: int

    def __post_init__(self):
        # assign data_in only once, because random values are used
        range_ = range(self.height * self.width * self.depth)
        if self.name == "increment":
            self.data_in = [i % 256 for i in range_]
        elif self.name == "ones":
            self.data_in = [1 for _ in range_]
        elif self.name == "random":
            self.data_in = [randint(0, 255) for _ in range_]
        else:
            raise ValueError(f"invalid name {self.name}")

    @property
    def id_(self) -> str:
        return (f"{self.name}_{self.width}x{self.height}_"
                f"row_filter_{self.row_filter}_color_{self.color_type}_"
                f"btype_{self.block_type}")

    @property
    def depth(self) -> int:
        if self.color_type == 0:
            return 1  # gray
        elif self.color_type == 2:
            return 3  # RGB
        elif self.color_type == 3:
            return 1  # palette (TODO: is this correct?)
        elif self.color_type == 4:
            return 2  # gray with alpha
        elif self.color_type == 6:
            return 4  # RGB with alpha
        raise ValueError(f"invalid color type {self.color_type}")


def create_test_suite(tb_lib):
    root = dirname(__file__)
    os.makedirs(join(root, "gen"), exist_ok=True)

    tb_deflate = tb_lib.entity("tb_png_encoder")

    testcases = []
    for name, img_size, color_type, block_type, row_filter in itertools.product(
            ("increment", "ones", "random"), ((4, 4), (12, 12), (60, 80)),
            (0, 2, 4, 6), (0, 1), (0, 1)):
        if row_filter != 0 and img_size != (12, 12):
            continue  # skip some tests to reduce execution time

        testcases.extend([
            Testcase(name, *img_size, color_type, block_type, row_filter),
        ])

    # regression
    testcases.extend([
        Testcase("ones", 3, 5, 2, 1, 0),
        Testcase("ones", 5, 3, 4, 1, 0),
    ])

    # comparison to https://ipbloq.files.wordpress.com/2017/09/ipb-png-e-pb.pdf
    testcases.append(Testcase("ones", 800, 480, 2, 1, 0))

    for case in testcases:
        generics = {
            "id": case.id_,
            "C_IMG_WIDTH": case.width,
            "C_IMG_HEIGHT": case.height,
            "C_IMG_BIT_DEPTH": 8,
            "C_COLOR_TYPE": case.color_type,
            "C_INPUT_BUFFER_SIZE": 12,
            "C_SEARCH_BUFFER_SIZE": 12,
            "C_BTYPE": case.block_type,
            "C_ROW_FILTER_TYPE": case.row_filter,
            "C_MAX_MATCH_LENGTH_USER": 7,
        }
        tb_deflate.add_config(
            name=case.id_, generics=generics,
            pre_config=partial(create_stimuli, root, case),
            post_check=partial(assemble_and_check_png, root, case))
