
redo-ifchange ../runner/exectest.bin
redo-ifchange "$(find ../sut/*)"

../runner/exectest.bin \
  --sutdir "$(cd ../sut && pwd)" \
  --outdir "$(pwd)"


