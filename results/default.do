
redo-ifchange \
  ../tests/all \
  ../analysis/analyze.bin

../analysis/analyze.bin \
  --testdir "$(cd ../tests && pwd)" \
  --outdir "$(pwd)"

