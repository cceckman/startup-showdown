
for DIR in $(find ../sut -mindepth 1 -maxdepth 1 -type d)
do
  echo "$(basename $DIR)/out"
done \
  | xargs redo-ifchange

