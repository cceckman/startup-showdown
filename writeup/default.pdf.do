
redo-ifchange "$2".md

pandoc --pdf-engine=xelatex --to pdf "$2".md >"$3"

