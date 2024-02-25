
set -eu

redo-ifchange drop-caches

# Back up the perf setting, first:
echo >&2 "\
  I'm about to ask for sudo access for a few things:
  1)  Temporarily set kernel.perf_event_paranoid lower,
      so we can run traces without sudo
  2)  Make the drop-caches program setuid root,
      so we can run the 'no cache' tests without sudo
  3)  (Permanently) make the tracing tree accessible to you, as a member of
      the 'tracing' group

  I'll try to restore these when done - please approve!
"

OLD_PERFCTL="$(cat /proc/sys/kernel/perf_event_paranoid)"
# Prepare the cleanup before making any changes, so we unwind the changes
# if setting doesn't work:
cleanup() {
  set -x
  sudo sysctl -w kernel.perf_event_paranoid="$OLD_PERFCTL"
  # Don't even bother letting it be executable after we've run.
  sudo chmod 00644 ./drop-caches
  sudo chown "$USER":"$USER" ./drop-caches
  set +x
}
SAVE_TRAPS=$(trap)
trap cleanup EXIT ABRT TERM INT QUIT
(
  if id -Gn | grep -qv tracing
  then
    echo >&2 "You're not in the 'tracing' user group!"
    echo >&2 "I can try to fix that, but then you'll need to log in again."
    set -x
    sudo addgroup tracing || {
      EXITCODE="$?"
      set +x
      if test "$EXITCODE" -eq 1
      then
        echo >&2 "Great, the tracing group already exists!"
      else
        echo >&2 "Failed to create the tracing group"
        exit $EXITCODE
      fi
    }
    echo >&2 "Let's put you in the 'tracing' group: "
    set -x; sudo usermod -aG tracing "$USER"; set +x
    echo >&2 "Now log out and log in again to see the tracing group!"
    exit 1
  fi

  set -x
  sudo sysctl -w kernel.perf_event_paranoid=-1
  # The `perf` tool recommends:
  #   sudo mount -o remount,mode=755 /sys/kernel/tracing/
  # But per https://lore.kernel.org/all/2315137.Eos4xDj3du@milian-workstation/T/
  # this is not currently sufficient. Use the workaround:
  sudo chgrp -R tracing /sys/kernel/tracing

  # Mode: sticky UID+GID (6), user read+exec (5), same for group (5) and all (5)
  sudo chown root:root ./drop-caches
  sudo chmod 6555 ./drop-caches
  stat >&2 ./drop-caches
  eval "$SAVE_TRAPS"
  set +x
)

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
for MODE in base no_cache
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

