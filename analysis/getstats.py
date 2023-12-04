#! /usr/bin/env python3
"""
Collect statistics from startup-showdown test runs.
"""

import argparse
import typing
import os
import pathlib
import re
import statistics

class Stats():
    def __init__(self):
        self.data = []

        self.mean = 0.0
        self.median = 0.0
        self.min = 0.0
        self.max = 10000000.0

    def update(self, data : float):
        self.data.append(data)

    def _update_stats(self):
        self.mean = statistics.mean(self.data)
        self.median  = statistics.median(self.data)
        self.min = min(self.data)
        self.max = max(self.data)

    def __str__(self):
        self._update_stats()
        return f"""mean {self.mean}
median {self.median}
min {self.min}
max {self.max}
"""

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

def process_file(filepath: str) -> float:
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

def process(directory: pathlib.PurePath) -> Stats:
    result = Stats()
    for f in os.listdir(directory):
        elapsed = process_file(directory.joinpath(f))
        result.update(elapsed)
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory")
    args = parser.parse_args()
    stats = process(pathlib.PurePath(args.directory))
    print(stats)
