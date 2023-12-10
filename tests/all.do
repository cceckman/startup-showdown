
COUNT=10

# We run these tests with -j1 so they don't stomp on each other.

# Allow parallelism in building test binaries: invoke them all at once.
for DIR in $(find ../sut -mindepth 1 -maxdepth 1 -type d)
do
  SUT="$(basename $DIR)"
  echo "../sut/$SUT/test"
done \
  | xargs redo-ifchange

TARGETS="$(mktemp)"
for MODE in base no_cache all_syscalls
do
  for DIR in $(find ../sut -mindepth 1 -maxdepth 1 -type d | sort)
  do
    SUT="$(basename $DIR)"
    mkdir -p "${MODE}/${SUT}"
    for RUN in $(seq $COUNT)
    do
      # We intentionally unset MAKEFLAGS before generating the trace,
      # so the subprocess doesn't inherit our job server --> runs serially.
      # But we still get caching; use `redo clean` to get new tests results.
      MAKEFLAGS="" redo-ifchange "${MODE}/${SUT}/${RUN}.trace"

      # We'll process all the tracefiles into text in parallel.
      echo "${MODE}/${SUT}/${RUN}.stats" >>"$TARGETS"
    done
  done
done

# Now that we've produced all the raw trace files, convert them to text
# for "parsing".
<"$TARGETS" xargs redo-ifchange

