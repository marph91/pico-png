"""Test cases for the png_encoder module."""

from collections import namedtuple
import functools
import io
import itertools
import os
from os.path import join, dirname
from random import randint
from typing import List
import zlib

from PIL import Image


def create_stimuli(root: str, name: str, input_data: List[int]):
    # write out csv only for debugging purposes
    filename = join(root, "gen", f"input_{name}.csv")
    with open(filename, "w") as infile:
        infile.write(", ".join(map(str, input_data)))

    filename = join(root, "gen", f"input_{name}.raw")
    with open(filename, "wb") as infile:
        infile.write(bytes(input_data))  # only works for 8 bit values!


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
def assemble_and_check_png(root, input_data, name, width, depth):
    with open(join(root, "gen", f"png_{name}.txt"), "r") as infile:
        binary_strings = infile.readlines()

    png_bytes = bytearray()
    for byte_str in binary_strings:
        assert len(byte_str) == 9, len(byte_str)  # 8 bit + newline
        png_bytes.append(int(byte_str, 2))

    # switch header and data. header is sent later, because the chunk
    # length has to be specified there.
    # strip the last three bytes of the header. they are only padded.
    png_bytes = png_bytes[-44:-3] + png_bytes[:-44]
    with open(join(root, "gen", f"test_img_{name}.png"), "wb") as outfile:
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
    scanlines = [decoded_data[x:x + width*depth + 1]
                 for x in range(0, len(decoded_data), width*depth + 1)]
    reconstructed_data = []
    for line in scanlines:
        reconstructed_data.extend(apply_filter(line))

    print("input data:", input_data, list(input_data))
    print("reconstructed data:", reconstructed_data)
    return list(input_data) == reconstructed_data


def get_depth(color_type: int) -> int:
    if color_type == 0:
        return 1  # gray
    elif color_type == 2:
        return 3  # RGB
    elif color_type == 3:
        return 1  # palette (TODO: is this correct?)
    elif color_type == 4:
        return 2  # gray with alpha
    elif color_type == 6:
        return 4  # RGB with alpha
    raise ValueError(f"invalid color type {color_type}")


def create_test_suite(tb_lib):
    root = dirname(__file__)
    os.makedirs(join(root, "gen"), exist_ok=True)

    tb_deflate = tb_lib.entity("tb_png_encoder")

    # TODO: simplify test case generation (also use dataclasses, when
    #       python 3.7 is available at opensuse)
    Case = namedtuple("Case", ["name", "width", "height", "depth", "ctype",
                               "btype", "row_filter", "data_in"])
    testcases = []
    for width, height in ((4, 4), (12, 12), (60, 80)):
        for ctype in (0, 2, 4, 6):
            depth = get_depth(ctype)

            for row_filter, btype in itertools.product((0, 1), (0, 1)):
                if row_filter != 0 and width != 12 and height != 12:
                    continue  # skip some tests to reduce execution time

                testcases.extend([
                    Case("increment", width, height, depth, ctype, btype,
                         row_filter,
                         [i % 256 for i in range(height*width*depth)]),
                    Case("ones", width, height, depth, ctype, btype,
                         row_filter, [1 for _ in range(height*width*depth)]),
                    Case("random", width, height, depth, ctype, btype,
                         row_filter,
                         [randint(0, 255) for _ in range(height*width*depth)]),
                ])

    # regression
    testcases.extend([
        Case("ones", 3, 5, 3, 2, 1, 0, [1 for _ in range(3*5*3)]),
        Case("ones", 5, 3, 2, 4, 1, 0, [1 for _ in range(5*3*2)]),
    ])

    # comparison to https://ipbloq.files.wordpress.com/2017/09/ipb-png-e-pb.pdf
    height = 800
    width = 480
    ctype = 2
    depth = get_depth(ctype)
    testcases.extend([
        Case("ones", height, width, depth, ctype, 1, 0,
             [1 for _ in range(height*width*depth)]),
    ])

    for case in testcases:
        input_bytes = bytearray(case.data_in)

        id_ = (f"{case.name}_{case.width}x{case.height}_row_filter_"
               f"{case.row_filter}_color_{case.ctype}_btype_{case.btype}")
        generics = {
            "id": id_,
            "C_IMG_WIDTH": case.width,
            "C_IMG_HEIGHT": case.height,
            "C_IMG_BIT_DEPTH": 8,
            "C_COLOR_TYPE": case.ctype,
            "C_INPUT_BUFFER_SIZE": 12,
            "C_SEARCH_BUFFER_SIZE": 12,
            "C_BTYPE": case.btype,
            "C_ROW_FILTER_TYPE": case.row_filter,
        }
        tb_deflate.add_config(
            name=id_, generics=generics,
            pre_config=create_stimuli(root, id_, case.data_in),
            post_check=functools.partial(
                assemble_and_check_png, root, input_bytes, id_,
                case.width, case.depth))
