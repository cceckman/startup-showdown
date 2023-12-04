
redo-always

find . \
  -not \( -name .gitignore -or -name '*.do' -or -name '*.py' \) \
  -delete
