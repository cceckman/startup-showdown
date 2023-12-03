
SUT="$(basename "$(dirname "$1")")"
SUT_PATH="$(pwd)/../sut/$SUT/test"

redo-ifchange "$SUT_PATH"

mkdir -p "$(dirname $3)"

TRACEFILE="$(mktemp -u)"

# TODO: Controls and statistics.
# - Flushed page cache
# - Happy page cache
# - Multiple samples
# - CPU power controls (see if it matters?)
# - environment noise

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

