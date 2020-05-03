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

from vunit import VUnit


def create_stimuli(root: str, name: str, input_data: List[int]):
    filename = join(root, "gen", f"input_{name}.csv")
    with open(filename, "w") as infile:
        infile.write(", ".join(map(str, input_data)))


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


def create_test_suite(ui):
    root = dirname(__file__)
    os.makedirs(join(root, "gen"), exist_ok=True)

    ui.add_array_util()
    unittest = ui.add_library("unittest", allow_duplicate=True)
    unittest.add_source_files(join(root, "tb_png_encoder.vhd"))
    tb_deflate = unittest.entity("tb_png_encoder")

    # TODO: simplify test case generation
    # TODO: fix (5, 3)
    for width, height in ((1, 1), (4, 4), (12, 12), (60, 80)):
        Case = namedtuple("Case", ["name", "input_buffer_size",
                                   "search_buffer_size", "data_in"])
        for ctype in (0, 2, 4, 6):
            depth = get_depth(ctype)
            testcases = (
                Case("increment", 12, 12,
                     [i % 256 for i in range(height*width*depth)]),
                Case("ones", 12, 12, [1 for _ in range(height*width*depth)]),
                Case("random", 12, 12,
                     [randint(0, 255) for _ in range(height*width*depth)]),
            )

            # TODO: fix unequal input and search buffer size:
            #       unittest.tb_png_encoder.ones_12x12_row_filter_1_btype_1
            #       input buffer: 10, search buffer: 12

            for case, row_filter, btype in itertools.product(
                    testcases, (0, 1), (0, 1)):
                if row_filter != 0 and width != 12 and height != 12:
                    continue  # skip some tests to reduce execution time
                input_bytes = bytearray(case.data_in)

                id_ = (f"{case.name}_{width}x{height}_row_filter_{row_filter}"
                       f"_color_{ctype}_btype_{btype}")
                generics = {
                    "id": id_,
                    "C_IMG_WIDTH": width,
                    "C_IMG_HEIGHT": height,
                    "C_IMG_BIT_DEPTH": 8,
                    "C_COLOR_TYPE": ctype,
                    "C_INPUT_BUFFER_SIZE": case.input_buffer_size,
                    "C_SEARCH_BUFFER_SIZE": case.search_buffer_size,
                    "C_BTYPE": btype,
                    "C_ROW_FILTER_TYPE": row_filter,
                }
                tb_deflate.add_config(
                    name=id_, generics=generics,
                    pre_config=create_stimuli(root, id_, case.data_in),
                    post_check=functools.partial(
                        assemble_and_check_png, root, input_bytes, id_,
                        width, depth))


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
