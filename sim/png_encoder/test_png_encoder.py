"""Test cases for the png_encoder module."""

import dataclasses
import io
import itertools
import os
from os.path import join, dirname


# https://stackoverflow.com/questions/44624407/how-to-reduce-log-line-size-in-cocotb
os.environ["COCOTB_REDUCED_LOG_FMT"] = "1"


@dataclasses.dataclass
class Testcase:
    name: str
    width: int
    height: int
    color_type: int
    block_type: int
    row_filter: int

    @property
    def id_(self) -> str:
        return (f"{self.name}_{self.width}x{self.height}_"
                f"row_filter_{self.row_filter}_color_{self.color_type}_"
                f"btype_{self.block_type}")


def generate_testcases():
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
    return testcases


def create_test_suite(tb_lib):
    root = dirname(__file__)
    os.makedirs(join(root, "gen"), exist_ok=True)

    tb_png_encoder = tb_lib.entity("tb_png_encoder")

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
            # "id": case.id_,
            "C_IMG_WIDTH": case.width,
            "C_IMG_HEIGHT": case.height,
            "C_IMG_BIT_DEPTH": 8,
            "C_COLOR_TYPE": case.color_type,
            "C_INPUT_BUFFER_SIZE": 12,
            "C_SEARCH_BUFFER_SIZE": 12,
            "C_BTYPE": case.block_type,
            "C_ROW_FILTER_TYPE": case.row_filter,
        }
        tb_png_encoder.add_config(name=case.id_, generics=generics)
