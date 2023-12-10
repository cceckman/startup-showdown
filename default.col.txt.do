
# Nicely format a CSV file into columns.

OUT="$1"
OUT_MINUS_EXT="$2"
SRC="${OUT_MINUS_EXT}.csv"

set -eu
redo-ifchange "$SRC"
column -s, -t <"$SRC" >"$3"

