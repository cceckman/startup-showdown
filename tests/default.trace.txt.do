
# We depend on "all traces" rather than our specific one,
# because we don't want to re-run traces individually (avoiding performance
# interference).
redo-ifchange all-traces
perf script \
  -F trace:time,event,sym,trace \
  -i "$2".trace \
  >"$3"

