#!/bin/bash
set -euo pipefail

# 1) If not 'frappe', re-exec as 'frappe' with a login shell so ~/.profile is loaded.
if [ "$(id -un)" != "frappe" ]; then
  exec su -l frappe -c "bash -lc '/workspace/init.sh'"
fi

# 2) Baseline env (bench image normally sets these; we enforce for safety).
export HOME="${HOME:-/home/frappe}"
export PATH="/home/frappe/.nvm/versions/node/v${NODE_VERSION_DEVELOP}/bin:/home/frappe/.local/bin:/home/frappe/.pyenv/shims:/home/frappe/.pyenv/bin:${PATH}"
[ -f "/home/frappe/.profile" ] && source "/home/frappe/.profile" || true

# 3) Resolve Bench robustly: try symlink then pipx venvs (old & new layouts), then PATH.
CANDIDATES=(
  "/home/frappe/.local/bin/bench"
  "/home/frappe/.local/share/pipx/venvs/bench/bin/bench"
  "/home/frappe/.local/pipx/venvs/bench/bin/bench"
  "/usr/local/bin/bench"
)
BENCH=""
for c in "${CANDIDATES[@]}"; do
  if [ -x "$c" ]; then BENCH="$c"; break; fi
done
if [ -z "$BENCH" ] && command -v bench >/dev/null 2>&1; then
  BENCH="$(command -v bench)"
fi
if [ -z "$BENCH" ]; then
  echo "ERROR: bench not found."
  echo "Checked:"
  printf ' - %s\n' "${CANDIDATES[@]}"
  echo "PATH: $PATH"
  ls -al "/home/frappe/.local/bin" 2>/dev/null || true
  ls -al "/home/frappe/.local/share/pipx/venvs/bench/bin" 2>/dev/null || true
  ls -al "/home/frappe/.local/pipx/venvs/bench/bin" 2>/dev/null || true
  exit 1
fi

BENCH_DIR="/home/frappe/frappe-bench"
SITE="${HOSTNAME}"
SITE_DIR="${BENCH_DIR}/sites/${SITE}"

# Idempotent start if already initialized
if [ -d "${BENCH_DIR}/apps/frappe" ] && [ -d "${SITE_DIR}" ]; then
  echo "Bench & site exist, starting bench..."
  cd "${BENCH_DIR}"
  exec "${BENCH}" start
fi

# Initialize bench if missing
if [ ! -d "${BENCH_DIR}/apps/frappe" ]; then
  echo "Creating new bench at ${BENCH_DIR}..."
  "${BENCH}" init --skip-redis-config-generation "${BENCH_DIR}"
fi

cd "${BENCH_DIR}"

# Configure external services (expects SQL_URL like host or DSN; REDIS_URL like redis://[:pass@]host:6379)
[ -n "${SQL_URL:-}"   ] && [ "${SQL_URL}"   != "changeme" ] && "${BENCH}" set-mariadb-host "${SQL_URL}"
[ -n "${REDIS_URL:-}" ] && [ "${REDIS_URL}" != "changeme" ] && {
  "${BENCH}" set-redis-cache-host    "${REDIS_URL}"
  "${BENCH}" set-redis-queue-host    "${REDIS_URL}"
  "${BENCH}" set-redis-socketio-host "${REDIS_URL}"
}

# Clean Procfile of redis/watch (safe if absent)
sed -i '/redis/d' ./Procfile || true
sed -i '/watch/d' ./Procfile || true

# Get CRM if missing, create site, install app
[ -d "apps/crm" ] || "${BENCH}" get-app crm

if [ ! -d "${SITE_DIR}" ]; then
  echo "Creating site ${SITE}..."
  "${BENCH}" new-site "${SITE}" \
    --force \
    --mariadb-root-password "${MARIADB_ROOT_PASSWORD}" \
    --admin-password "${SITE_ADMIN_PASSWORD}" \
    --no-mariadb-socket
fi

"${BENCH}" --site "${SITE}" install-app crm
"${BENCH}" --site "${SITE}" set-config developer_mode 1
"${BENCH}" --site "${SITE}" clear-cache
"${BENCH}" use "${SITE}"

exec "${BENCH}" start
