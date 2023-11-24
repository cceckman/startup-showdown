
redo-always

find . \
  -not \( -name .gitignore -or -name '*.do' \) \
  -delete
