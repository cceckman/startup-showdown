
redo-ifchange "$2".md

pandoc --to odt "$2".md >"$3"
