#!/bin/sh

set -eu

# Run and trace a test binary.
MODE="$1"
SUT="$2"
RUN="$3"

SUT_PATH="$(pwd)/../sut/$SUT/test"

# TODO: Controls and statistics.
# - Happy page cache
# - Multiple samples
# - CPU power controls (see if it matters?)
# - CPU affinity (see if it matters?)
# - environment noise

# This won't do much for libc, but that's fine
if echo "$MODE" | grep -q "no_cache"
then
  # sync filesystems
  sync
  # drop caches: page cache (file contents) and filesystem caches
  # (directory entries, inodes)
  ./drop-caches.sh
  # The above will simulate "a command we haven't used in a while", though
  # stuff that is commonly used by other utilities will arrive back in quickly.
  #
  # In particular, libc will probably be faulted back in almost immediately
  # by `sudo` and/or `perf` and/or the shell running this script.
  #
  # That's kinda fine- it matches what we'd see during "normal operation" of
  # this system. If the parent system doesn't use those, then we won't see them!
fi

# We always want these syscall events;
# we use them for computing latency.
SYSCALL_EVENTS="syscalls:sys_exit_execve,syscalls:sys_enter_write"

if echo "$MODE" | grep -q "all_syscall"
then
  # Add all syscalls: gives is more data too see what the program asked for.
  SYSCALL_EVENTS="syscalls:*"
fi

OUT="${MODE}/${SUT}/${RUN}.trace"

perf record \
  --output "$OUT" \
  --event  "$SYSCALL_EVENTS" \
  "$SUT_PATH"



