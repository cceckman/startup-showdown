
SUT="$(basename "$(dirname "$1")")"
SUT_PATH="$(pwd)/../sut/$SUT/test"

redo-ifchange "$SUT_PATH"

mkdir -p "$(dirname $3)"

TRACEFILE="$(mktemp -u)"

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

