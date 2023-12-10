
redo-ifchange "$2".trace
perf script \
  -F trace:time,event,sym,trace \
  -i "$2".trace \
  >"$3"

