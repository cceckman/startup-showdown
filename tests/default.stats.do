
SUT="$(basename "$(dirname "$1")")"
SUT_PATH="$(pwd)/../sut/$SUT/test"

redo-ifchange "$SUT_PATH"

TRACEFILE="$(mktemp -u)"

# TODO: Controls and statistics.
# - Flushed page cache
# - Happy page cache
# - Multiple samples
# - CPU power controls (see if it matters?)
# - CPU affinity (see if it matters?)
# - environment noise

# This won't do much for libc, but that's fine
if echo "$1" | grep -q "nocache"
then
  # sync filesystems
  sync
  # drop caches: page cache (file contents) and filesystem caches
  # (directory entries, inodes)
  echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
  # The above will simulate "a command we haven't used in a while", though
  # stuff that is commonly used by other utilities will arrive back in quickly.
  #
  # In particular, libc will probably be faulted back in almost immediately
  # by `sudo` and/or `perf` and/or the shell running this script.
  #
  # That's kinda fine- it matches what we'd see during "normal operation" of
  # this system. If the parent system doesn't use those, then we won't see them!
fi

sudo \
  perf record \
  -o "$TRACEFILE" \
  -e syscalls:sys_exit_execve,syscalls:sys_enter_write \
  "$SUT_PATH" \
  >/dev/null
sudo chmod 0644 "$TRACEFILE"
perf script \
  -F trace:time,event,sym,trace \
  -i "$TRACEFILE" \
  >"$3"

sudo rm "$TRACEFILE"