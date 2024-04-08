#!/usr/bin/env python3
"""
CSV-ize samples from startup-showdown.
"""

import argparse
import copy
import importlib
import itertools
import os
import pathlib
import re
import subprocess
import sys
import typing

sys.path.append(".")
Sample = importlib.import_module("sample").Sample

# On my system, `perf` is returning results in microseconds.
# We typically have 53 bits of precision in a Python float - from the
# IEEE 754 double format.
# If that's true, we have:
# >>> (2 ** 53) / 1000 / 1000 / 60 / 60 / 24 / 365
# 285.61641472415624
# years of uptime before we start losing precision...and honestly, we shouldn't
# expect accuracy at sub-microsecond either.
# So we can just conver these to float, without really worrying about lost
# precision.
START = re.compile("^(\d+\.\d+).*sys_exit_exec")
WRITE = re.compile("^(\d+\.\d+).*sys_enter_write.*fd: (0[xX])?0*1\D")

def get_latency(filepath: pathlib.Path) -> float:
    """Returns the elapsed time from the file.

    Args:
        filepath: `perf report` output file. Must have leading timestamps and
            trace arguments as from:
            `perf script -F trace:time,event,sym,trace`
    Returns:
        Time from first `exec` to `write`
    """

    with open(filepath) as f:
        # Match the first line to the start timestamp
        m = START.match(f.readline())
        if m is None:
            raise Exception(f"found no starting match in {filepath}")
        start = float(m.group(1))
        for line in f.readlines():
            m = WRITE.match(line)
            if m is None:
                continue
            write = float(m.group(1))
            return write - start
    raise Exception(f"found no timestamp match in {filepath}")

def get_samples() -> typing.Generator[Sample, None, None]:
  """Process all source files into Sample strucsts.

  Yields:
    Sample structs
  """
  for mode in os.scandir("."):
    if not mode.is_dir():
      continue
    for sut in os.scandir(mode.path):
      if not sut.is_dir():
        continue
      for case in os.scandir(sut.path):
        path = pathlib.Path(case.path)
        if path.suffixes != [".trace", ".txt"]:
          continue
        latency = get_latency(path)
        yield Sample(mode.name, sut.name, latency, str(path))

def lines(outpath: pathlib.Path):
  """Writes CSV lines from input source files."""

  samples = list(get_samples())
  Sample.csv_write(outpath, samples)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("output") # Output buffer
    args = parser.parse_args()
    lines(pathlib.Path(args.output))

