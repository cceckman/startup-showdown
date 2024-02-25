
redo-always
redo \
  sut/clean \
  tests/clean \
  analysis/clean
find . -name '*.did' -or -name '*.did.tmp' -delete

