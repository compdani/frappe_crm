#!/bin/bash
set -euo pipefail

# Ensure expected HOME and PATH (platforms sometimes override these)
export HOME="${HOME:-/home/frappe}"
export PATH="/home/frappe/.local/bin:/home/frappe/.pyenv/shims:/home/frappe/.pyenv/bin:${PATH}"

# Load profile if present (pipx + pyenv often wired here)
if [ -f "/home/frappe/.profile" ]; then
  # shellcheck disable=SC1090
  source /home/frappe/.profile
fi

# Resolve bench command robustly
BENCH="${BENCH_CMD:-/home/frappe/.local/bin/bench}"
if ! command -v "${BENCH}" >/dev/null 2>&1; then
  if command -v bench >/dev/null 2>&1; then
    BENCH="$(command -v bench)"
  else
    echo "bench not found on PATH; attempting to install via pipx..."
    # Last-resort: install bench for current user
    python3 -m pip install --user bench || pip3 install --user bench
    hash -r
    BENCH="$(command -v bench || echo /home/frappe/.local/bin/bench)"
    if ! [ -x "${BENCH}" ]; then
      echo "ERROR: bench still not available after install." >&2
      exit 1
    fi
  fi
fi

# Optional Node path for developer mode
export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"

if [ -d "/home/frappe/frappe-bench/apps/frappe" ]; then
  echo "Bench already exists, skipping init"
  cd /home/frappe/frappe-bench
  exec "${BENCH}" start
fi

echo "Creating new bench..."
"${BENCH}" init --skip-redis-config-generation /home/frappe/frappe-bench
cd /home/frappe/frappe-bench

# Use containers instead of localhost
"${BENCH}" set-mariadb-host "${SQL_URL}"
"${BENCH}" set-redis-cache-host "${REDIS_URL}"
"${BENCH}" set-redis-queue-host "${REDIS_URL}"
"${BENCH}" set-redis-socketio-host "${REDIS_URL}"

# Remove redis, watch from Procfile
# Remove redis, watch from Procfile
sed -i '/redis/d' ./Procfile || true
sed -i '/watch/d' ./Procfile || true

"${BENCH}" get-app crm

"${BENCH}" new-site "${}" \
  --force \
  --mariadb-root-password "${MARIADB_ROOT_PASSWORD}" \
  --admin-password "${SITE_ADMIN_PASSWORD}" \
  --no-mariadb-socket


"${BENCH}" --site crm.localhost install-app crm
"${BENCH}" --site crm.localhost set-config developer_mode 1
"${BENCH}" --site crm.localhost clear-cache
"${BENCH}" use crm.localhost

exec "${BENCH}" start
