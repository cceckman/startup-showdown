
# Nicely format a CSV file into columns.

OUT="$1"
OUT_MINUS_EXT="$2"
SRC="${OUT_MINUS_EXT}.csv"

set -eu
redo-ifchange "$SRC"

TEMP="$(mktemp)"
<"$SRC" column -s, -t -o' | ' >"$TEMP"

# Now that everything is nicely in columns, add the header separator:
<"$TEMP" head -1 >"$3"
<"$TEMP" head -1 | sed 's/[^|]/-/g' >>"$3"
<"$TEMP" tail -n+2 >>"$3"

