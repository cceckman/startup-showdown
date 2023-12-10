
redo-ifchange ../analysis/extract-metrics.py ../analysis/sample.py
find . -name '*.stats' | xargs redo-ifchange

exec ../analysis/extract-metrics.py "$3"
