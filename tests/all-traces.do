
set -eu

COUNT=10

# We run all the tests from one file so they don't interfere with each other.

# Allow parallelism in building test binaries: invoke them all at once.
for DIR in $(find ../sut -mindepth 1 -maxdepth 1 -type d)
do
  SUT="$(basename $DIR)"
  echo "../sut/$SUT/test"
done \
  | xargs redo-ifchange

redo-ifchange run-trace.sh

echo >&2 "Starting sampling runs..."
TARGETS="$(mktemp)"
for MODE in base no_cache all_syscalls
do
  for DIR in $(find ../sut -mindepth 1 -maxdepth 1 -type d | sort)
  do
    SUT="$(basename $DIR)"
    mkdir -p "${MODE}/${SUT}"
    for RUN in $(seq $COUNT)
    do
      echo >&2 "$MODE": "$SUT" "#$RUN"
      ./run-trace.sh "$MODE" "$SUT" "$RUN"
    done
  done
done
echo >&2 "Completed sampling runs."

# As an output, mark what we produced.
find . -name "*.trace" | xargs sha256sum >"$3"

