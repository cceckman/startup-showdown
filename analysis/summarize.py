#! /usr/bin/env python3
"""
Collect statistics from startup-showdown test runs.
"""

from collections.abc import Iterator
from pathlib import Path
from typing import Self
import argparse
import collections
import csv
import importlib
import pathlib
import re
import statistics
import sys
import typing

sys.path.append('.')
Sample = importlib.import_module("sample").Sample

class Stats():
    """Statistics for a group of runs.

    All runs should be consistent, i.e. a single system-under-test.
    The test case is given by the name.
    """

    def __init__(self, samples: list[Sample]):
        if len(samples) == 0:
            raise Exception("no samples in list")
        self.mode = samples[0].mode
        self.sut = samples[0].sut

        data = []
        for sample in samples:
            assert(sample.mode == self.mode)
            assert(sample.sut == self.sut)
            data.append(sample.latency)

        # We round to the nearest microsecond- we aren't _that_ precise.
        rnd = lambda x: round(x, 4)

        self.mean = rnd(statistics.mean(data))
        self.median = rnd(statistics.median(data))
        self.min = min(data)
        self.max = max(data)

    @staticmethod
    def csv_write(path: pathlib.Path, stats: Iterator[typing.Self]):
        with path.open("w") as f:
            w = csv.DictWriter(f, ["mode", "sut", "mean", "median", "min", "max"])
            w.writeheader()
            for stat in stats:
                w.writerow(stat.__dict__)

def process_samples(samples_csv: pathlib.Path) -> dict[str, list[Stats]]:
    # Dictionary: mode -> sut -> Stats
    data = collections.defaultdict(
            lambda: collections.defaultdict(list))
    for sample in Sample.read_file(samples_csv):
        data[sample.mode][sample.sut].append(sample)

    # Dictionary: mode -> list (by median) of Stats
    processed_data = {}
    for mode, suts in data.items():
        processed_data[mode] = []
        for sut, samples in suts.items():
            stats = Stats(samples)
            processed_data[mode].append(stats)
        processed_data[mode].sort(key = lambda stats: stats.mean)
    return processed_data

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("input_csv")
    parser.add_argument("output_csv")
    args = parser.parse_args()

    # For the purposes of printing, we don't need to have the nested
    # (mode, results) structure.
    all_stats = []
    for mode, sut_stats in process_samples(pathlib.Path(args.input_csv)).items():
        sys.stderr.write(f"processing {mode}: {len(sut_stats)} entries\n")
        all_stats += sut_stats

    Stats.csv_write(pathlib.Path(args.output_csv), all_stats)

