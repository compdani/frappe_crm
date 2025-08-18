#!/bin/bash
set -euo pipefail

# --- If we're NOT the frappe user, re-exec as frappe with a login shell ---
if [ "$(id -un)" != "frappe" ]; then
  exec su -l frappe -c "bash -lc '/workspace/init.sh'"
fi

# Ensure expected HOME and PATH (platforms sometimes override these)
export HOME="${HOME:-/home/frappe}"
export PATH="/home/frappe/.local/bin:/home/frappe/.pyenv/shims:/home/frappe/.pyenv/bin:${PATH}"

# Load profile if present (pipx/pyenv/nvm wiring)
[ -f "/home/frappe/.profile" ] && source "/home/frappe/.profile" || true

# Optional Node path for developer mode (some custom scripts expect this)
export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"

# Resolve bench (don’t try to install it; base image already has it)
BENCH="${BENCH_CMD:-/home/frappe/.local/bin/bench}"
if ! [ -x "$BENCH" ]; then
  # fallback to whatever is on PATH (should be set by base image)
  if command -v bench >/dev/null 2>&1; then
    BENCH="$(command -v bench)"
  else
    echo "ERROR: bench not found. PATH=$PATH" >&2
    exit 1
  fi
fi

# Idempotency checks
BENCH_DIR="/home/frappe/frappe-bench"
SITE_DIR="${BENCH_DIR}/sites/${HOSTNAME}"

if [ -d "${BENCH_DIR}/apps/frappe" ] && [ -d "${SITE_DIR}" ]; then
  echo "Bench & site already exist (${SITE_DIR}), starting bench..."
  cd "${BENCH_DIR}"
  exec "$BENCH" start
fi

if [ ! -d "${BENCH_DIR}/apps/frappe" ]; then
  echo "Creating new bench at ${BENCH_DIR}..."
  "$BENCH" init --skip-redis-config-generation "${BENCH_DIR}"
fi

cd "${BENCH_DIR}"

# Configure external services via provided URLs
# SQL_URL can be a hostname or DSN; bench accepts either (hostname preferred).
# REDIS_URL must be a redis URL like: redis://[:password@]host:6379
if [ -n "${SQL_URL:-}" ] && [ "${SQL_URL}" != "changeme" ]; then
  "$BENCH" set-mariadb-host "${SQL_URL}"
fi
if [ -n "${REDIS_URL:-}" ] && [ "${REDIS_URL}" != "changeme" ]; then
  "$BENCH" set-redis-cache-host    "${REDIS_URL}"
  "$BENCH" set-redis-queue-host    "${REDIS_URL}"
  "$BENCH" set-redis-socketio-host "${REDIS_URL}"
fi

# Clean Procfile entries for redis/watch (idempotent)
sed -i '/redis/d' ./Procfile || true
sed -i '/watch/d' ./Procfile || true

# Get CRM app if not present
if ! [ -d "apps/crm" ]; then
  "$BENCH" get-app crm
fi

# Create site if missing
if [ ! -d "${SITE_DIR}" ]; then
  echo "Creating site ${HOSTNAME}..."
  "$BENCH" new-site "${HOSTNAME}" \
    --force \
    --mariadb-root-password "${MARIADB_ROOT_PASSWORD}" \
    --admin-password "${SITE_ADMIN_PASSWORD}" \
    --no-mariadb-socket
fi

# Install & configure
"$BENCH" --site "${HOSTNAME}" install-app crm
"$BENCH" --site "${HOSTNAME}" set-config developer_mode 1
"$BENCH" --site "${HOSTNAME}" clear-cache
"$BENCH" use "${HOSTNAME}"

# Start forever (PID 1)
exec "$BENCH" start
