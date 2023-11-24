
redo-ifchange all
for f in $(ls */test.* | grep -v 'do')
do
  test "$($f)" = "Hello, world!" || {
    echo >&2 "$f failed"
    exit 1
  }
  echo >&2 "$f passed"
done
echo >&2 "all passed"
