
# Make a binary that drops kernel caches.
redo-ifchange drop-caches.c
cc -o "$3" drop-caches.c

