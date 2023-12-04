
COUNT=10

# We run these tests with -j1 so they don't stomp on each other.

for MODE in base nocache
do
  for DIR in $(find ../sut -mindepth 1 -maxdepth 1 -type d | sort)
  do
    SUT="$(basename $DIR)"
    redo-ifchange "../sut/$SUT/test"
    mkdir -p "${MODE}/${SUT}"
    for RUN in $(seq $COUNT)
    do
      redo -j1 "${MODE}/${SUT}/${RUN}.stats"
    done
  done
done
