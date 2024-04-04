
redo-ifchange sea-config.json app.js

# Using https://nodejs.org/docs/latest-v19.x/api/single-executable-applications.html
node --experimental-sea-config sea-config.json

cp $(command -v node) "$3"

exec >&2
npx postject "$3" NODE_SEA_BLOB sea-prep.blob \
    --sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2

