
# Build script for the test-result analyzer.
# For now, we'll do something silly:

cat <<EOF >"$3"
#!/bin/sh
echo >&2 "Faking analysis runs..."
echo >&2 "\$@"
EOF
chmod +x "$3"
