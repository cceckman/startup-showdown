
find src/ -type f | xargs redo-ifchange
redo-ifchange Cargo.toml

cargo build

cp target/*/hello-world "$3"

