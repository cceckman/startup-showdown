
redo-always

find . \
  -not \( -name .gitignore -or -name '*.do' -or -name '*.py' -or -name '*.sh' -or -name '*.c' \) \
  -delete

