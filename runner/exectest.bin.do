
# Build script for the test executor.
# For now, we'll do something silly:

cat <<EOF >"$3"
#!/bin/sh
echo >&2 "Faking test runs..."
echo >&2 "\$@"
EOF
chmod +x "$3"
