
# We don't trigger tests ourselves- just consume their results.
redo-ifchange ../analysis/extract-metrics.py ../analysis/sample.py

if test -z "$(find . -name '*.stats')"
then
  echo >&2 "No test results; rerunning tests/all..."
  redo all
fi

find . -name '*.stats' | xargs redo-ifchange

exec ../analysis/extract-metrics.py "$3"
