#! /usr/bin/env python3
# -*- coding: utf-8 -*-
# vim:fenc=utf-8
#
# Copyright © 2023 cceckman <charles@cceckman.com>
#
# Distributed under terms of the MIT license.

import csv
from typing import Self
from collections.abc import Iterator
from pathlib import Path

class Sample:
    """The results from a single test run."""

    def __init__(self, mode, sut, latency, path):
        self.mode = mode
        self.sut = sut
        # We round to the nearest 100 microseconds; I don't think our tracing is
        # any shorter than that.
        self.latency = round(float(latency), 4)
        self.path = path

    def _csv_append(self, w: csv.DictWriter):
        w.writerow({"mode": self.mode, "sut": self.sut, "latency": self.latency, "path": self.path})

    @staticmethod
    def csv_write(path: Path, samples: Iterator[Self]):
        with path.open('w') as f:
            w = csv.DictWriter(f, ["mode", "sut", "latency", "path"])
            w.writeheader()
            for sample in samples:
                sample._csv_append(w)

    @staticmethod
    def read_file(path: Path) -> list[Self]:
        result = []
        with path.open() as f:
            # Use the file header as the contents
            reader = csv.DictReader(f)
            for row in reader:
                result.append(Sample(**row))
        return result


