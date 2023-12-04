
for CASE in $(cd ../tests; find . -mindepth 2 -maxdepth 2 -type d)
do
  mkdir -p "$CASE"
  redo "$CASE"/stats
done
