
# We don't trigger tests ourselves- just consume their results.
redo-ifchange ../analysis/extract-metrics.py ../analysis/sample.py

if test -z "$(find . -name '*.trace')"
then
  echo >&2 "No test results; rerunning all traces"
  redo all-traces
fi

# Parse all the textfiles
find . -name "*.trace" \
  | sed -i 's/.trace$/.trace.txt/' \
  | xargs redo-ifchange

find . -name '*.stats' | xargs redo-ifchange

exec ../analysis/extract-metrics.py "$3"
