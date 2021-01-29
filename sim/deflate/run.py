"""Test cases for the deflate implementation."""

# further resources:
# https://tu-dresden.de/ing/informatik/ti/vlsi/ressourcen/dateien/dateien_studium/dateien_lehstuhlseminar/vortraege_lehrstuhlseminar/folder-2014-05-07-1069029811/Luhao-Liu_Defense-of-Project-Work.pdf?lang=de
# https://www.cse.wustl.edu/~roger/565M.f12/06270677.pdf
# https://dspace.cvut.cz/bitstream/handle/10467/82569/F8-DP-2019-Benes-Tomas-thesis.pdf?sequence=-1&isAllowed=y

# "pic":
# throughput at 100MHz: 27010728,6933 Byte/s (513216 Byte / 19.00045 ms)
# compression ratio: 3.401056335694736 (513216 Byte / 150899 Byte)

from functools import partial
from io import BytesIO
import os
from os.path import join, dirname
from pathlib import Path
import zipfile

import requests

from vunit import VUnit


def get_calgary_corpus(filename):
    """Download the calgary corpus and extract it if needed."""
    response = requests.get("http://www.data-compression.info/files/corpora/calgarycorpus.zip")
    response.raise_for_status()
    if filename != "complete":
        filebytes = BytesIO(response.content)
        with zipfile.ZipFile(filebytes) as myzip:
            with myzip.open(filename) as infile:
                return infile.read()
    return response.content


def create_stimuli(root, filename):
    filepath = Path(f"{root}/gen/{filename}.csv")
    if not filepath.is_file():
        data = get_calgary_corpus(filename)
        # convert bytes to csv of integers and save it
        with open(filepath.resolve(), "w") as outfile:
            outfile.write(",".join([str(byte_) for byte_ in data]))
    return True


def create_test_suite(tb_lib):
    root = dirname(__file__)
    os.makedirs(join(root, "gen"), exist_ok=True)

    tb_deflate = tb_lib.entity("tb_deflate")

    filename = "obj1"
    generics = {
        "filename": filename,
        "C_INPUT_BUFFER_SIZE": 12,
        "C_SEARCH_BUFFER_SIZE": 12,
        "C_BTYPE": 1,
    }
    tb_deflate.add_config(
        name="tb_deflate", generics=generics,
        pre_config=partial(create_stimuli, root, filename))
