
COUNT=10

# We run these tests with -j1 so they don't stomp on each other.

# Allow parallelism in building test binaries: invoke them all at once.
for DIR in $(find ../sut -mindepth 1 -maxdepth 1 -type d)
do
  SUT="$(basename $DIR)"
  echo "../sut/$SUT/test"
done \
  | xargs redo-ifchange

for MODE in base no_cache all_syscalls
do
  for DIR in $(find ../sut -mindepth 1 -maxdepth 1 -type d | sort)
  do
    SUT="$(basename $DIR)"
    mkdir -p "${MODE}/${SUT}"
    for RUN in $(seq $COUNT)
    do
      # We intentionally unset MAKEFLAGS, so the subprocess doesn't inherit
      # our job server --> runs serially.
      # But we still get caching; `redo clean` to get new tests results.
      MAKEFLAGS="" redo-ifchange "${MODE}/${SUT}/${RUN}.stats"
    done
  done
done

