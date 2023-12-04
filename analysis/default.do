
TARGET="$(dirname $(realpath $1))"

SUT="$(basename $TARGET)"
MODE="$(basename $(dirname $TARGET))"

SOURCES="../tests/${MODE}/${SUT}"

find "$SOURCES" -type f \
  | xargs redo-ifchange

redo-ifchange getstats.py
./getstats.py "$SOURCES" >"$3"

