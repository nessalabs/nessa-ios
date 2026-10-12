#!/usr/bin/env python3
"""Publish into an exclusively reserved fresh destination without nesting."""
import os
import pathlib
import shutil
import sys

source, destination = map(pathlib.Path, sys.argv[1:])
# mkdir is exclusive even when another producer creates the destination during
# compilation. Reserve only after the package is complete; preserve competitors.
destination.mkdir()
try:
    for entry in source.iterdir():
        os.rename(entry, destination / entry.name)
except BaseException:
    shutil.rmtree(destination)
    raise
