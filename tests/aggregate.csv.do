#!/usr/bin/env python3
"""
CSV-ize samples from startup-showdown.
"""

import argparse
import copy
import csv
import itertools
import os
import pathlib
import re
import subprocess
import typing

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

def get_latency(filepath: str) -> float:
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
        start = float(m.group(1))
        for line in f.readlines():
            m = WRITE.match(line)
            if m is None:
                continue
            write = float(m.group(1))
            return write - start
    raise Exception(f"found no timestamp match in {filepath}")

def enumerate_sources() -> typing.Generator[typing.Tuple[str, str, str], None, None]:
  """Enumerate all source files in the current directory.

  Yields:
    (mode, system-under-test, path) tuples
  """
  for mode in os.scandir("."):
    if not mode.is_dir():
      continue
    for sut in os.scandir(mode.path):
      if not sut.is_dir():
        continue
      for case in os.scandir(sut.path):
        yield (mode.name, sut.name, case.path)


def redo_ifchange(files: typing.List[str]):
  """Informs redo-ifchange of files used"""

  # Unset MAKEFLAGS so redo-ifchange doesn't try to reauth to the jobserver.
  # That's fine - it shouldn't be actually rebuilding these anyway.
  newenv = copy.deepcopy(os.environ)
  del newenv["MAKEFLAGS"]

  # Don't put too many on a line - same as xargs.
  # (This would be `batched` in 3.12, but Debian only has 3.11 so far)
  while len(files) != 0:
    nextlen = min(len(files), 10)
    myfiles, files = files[:nextlen], files[nextlen:]
    subprocess.run(["redo-ifchange"] + myfiles, check=True, env = newenv)

def lines(outpath: pathlib.Path):
  """Writes CSV lines from input source files."""

  files = []

  with outpath.open('w') as f:
    fields = ["mode", "sut", "latency", "path"]
    wr = csv.DictWriter(f, fields)
    wr.writeheader()
    for (mode, sut, path) in enumerate_sources():
      latency = get_latency(path)
      wr.writerow({"mode": mode, "sut": sut, "latency": latency, "path": path})
      files.append(path)

  redo_ifchange(files)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    # Standard redo arguments:
    parser.add_argument("target") # $1: What we're asked to build
    parser.add_argument("parent") # $2: Parent directory thereof
    parser.add_argument("output") # $3: Output buffer, to be renamed or deleted
    args = parser.parse_args()
    lines(pathlib.Path(args.output))

