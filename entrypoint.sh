#!/bin/sh
set -e

# Default to current host values if provided by compose; fallback to 1000
R_UID="${UID:-1000}"
R_GID="${GID:-1000}"

# Ensure /work exists and is writable by that uid:gid
mkdir -p /work
chown -R "$R_UID:$R_GID" /work

# Run the installer as the requested uid:gid
exec su-exec "$R_UID:$R_GID" python3 /usr/local/bin/easy-install.py "$@"
