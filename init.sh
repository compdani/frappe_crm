#!/bin/bash
set -euo pipefail

: "${BENCH_DIR:=/home/frappe/frappe-bench}"

# 0) If BENCH_DIR exists but isn't owned by frappe (common with volumes), fix it as root
if [ -d "$BENCH_DIR" ]; then
  bench_owner="$(stat -c '%U:%G' "$BENCH_DIR" || echo '')"
  if [ "$bench_owner" != "frappe:frappe" ]; then
    echo "Fixing ownership of ${BENCH_DIR} -> frappe:frappe (volume likely created as root)"
    chown -R frappe:frappe "$BENCH_DIR"
  fi
fi

# 1) Re-exec as 'frappe' with login shell so PATH/env from base image applies
if [ "$(id -un)" != "frappe" ]; then
  exec su -l frappe -c "bash -lc '/workspace/init.sh'"
fi

# 2) Ensure expected HOME/PATH; Bench and pipx live in ~/.local
export HOME="${HOME:-/home/frappe}"
export PATH="/home/frappe/.local/bin:/home/frappe/.pyenv/shims:/home/frappe/.pyenv/bin:${PATH}"
[ -f "/home/frappe/.profile" ] && source "/home/frappe/.profile" || true
export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"

# 3) Resolve Bench in all common pipx locations (symlink or venv)
CANDIDATES=(
  "/home/frappe/.local/bin/bench"
  "/home/frappe/.local/share/pipx/venvs/bench/bin/bench"
  "/home/frappe/.local/pipx/venvs/bench/bin/bench"
  "$(command -v bench || true)"
)
BENCH=""
for c in "${CANDIDATES[@]}"; do
  [ -x "$c" ] && BENCH="$c" && break
done
if [ -z "$BENCH" ]; then
  echo "ERROR: bench not found on PATH or expected locations."
  exit 1
fi

SITE="${HOSTNAME}"

# 4) If BENCH_DIR doesn't look initialized, init it; else just use it
if [ ! -d "${BENCH_DIR}/apps/frappe" ]; then
  echo "Creating new bench at ${BENCH_DIR}..."
  "$BENCH" init --skip-redis-config-generation "${BENCH_DIR}"
fi

# **Always** run bench commands from inside the bench dir
cd "${BENCH_DIR}"

# 5) Make sure we can write to sites/ (volume perms)
if [ ! -w "./sites" ]; then
  echo "ERROR: ./sites is not writable by user 'frappe'. Check your volume permissions."
  exit 1
fi

# 6) Configure external services (writes to sites/common_site_config.json)
#    If 'set-mariadb-host' fails on your bench version, you can use: bench set-config -g db_host HOST
if [ -n "${SQL_URL:-}" ] && [ "${SQL_URL}" != "changeme" ]; then
  if "$BENCH" --help | grep -q "set-mariadb-host"; then
    "$BENCH" set-mariadb-host "${SQL_URL}"
  else
    "$BENCH" set-config -g db_host "${SQL_URL}"
  fi
fi

if [ -n "${REDIS_URL:-}" ] && [ "${REDIS_URL}" != "changeme" ]; then
  "$BENCH" set-redis-cache-host    "${REDIS_URL}"
  "$BENCH" set-redis-queue-host    "${REDIS_URL}"
  "$BENCH" set-redis-socketio-host "${REDIS_URL}"
fi

# 7) Clean Procfile entries for redis/watch (idempotent)
sed -i '/redis/d' ./Procfile || true
sed -i '/watch/d' ./Procfile || true

# 8) Get CRM app if missing
[ -d "apps/crm" ] || "$BENCH" get-app crm

# 9) Create site if missing, then install app and set defaults
SITE_DIR="${BENCH_DIR}/sites/${SITE}"
if [ ! -d "${SITE_DIR}" ]; then
  echo "Creating site ${SITE}..."
  "$BENCH" new-site "${SITE}" \
    --force \
    --mariadb-root-password "${MARIADB_ROOT_PASSWORD}" \
    --admin-password "${SITE_ADMIN_PASSWORD}" \
    --no-mariadb-socket
fi

"$BENCH" --site "${SITE}" install-app crm
"$BENCH" --site "${SITE}" set-config developer_mode 1
"$BENCH" --site "${SITE}" clear-cache
"$BENCH" use "${SITE}"

exec "$BENCH" start