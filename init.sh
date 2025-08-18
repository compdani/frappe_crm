#!/bin/bash
set -e

# --- simple PATH so bench is found; add your dev Node if present
export PATH="/home/frappe/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH}"
if [ -n "${NVM_DIR:-}" ] && [ -n "${NODE_VERSION_DEVELOP:-}" ] \
   && [ -d "${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin" ]; then
  export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin:${PATH}"
fi

BENCH="${BENCH_CMD:-bench}"
BENCH_DIR="/home/frappe/frappe-bench"

# If a bench already exists, just start it
if [ -d "${BENCH_DIR}/apps/frappe" ]; then
  echo "Bench already exists, skipping init"
  cd "${BENCH_DIR}"
  exec "${BENCH}" start
else
  echo "Creating new bench..."
fi

# Create a fresh bench in the standard location
"${BENCH}" init --skip-redis-config-generation "${BENCH_DIR}"

cd "${BENCH_DIR}"

# Point bench to your external DB + Redis (skip if envs are unset/placeholder)
if [ -n "${SQL_URL:-}" ] && [ "${SQL_URL}" != "changeme" ]; then
  "${BENCH}" set-mariadb-host "${SQL_URL}"
fi

if [ -n "${REDIS_URL:-}" ] && [ "${REDIS_URL}" != "changeme" ]; then
  "${BENCH}" set-redis-cache-host    "${REDIS_URL}"
  "${BENCH}" set-redis-queue-host    "${REDIS_URL}"
  "${BENCH}" set-redis-socketio-host "${REDIS_URL}"
fi

# Remove redis/watch procs (only if Procfile exists)
if [ -f "./Procfile" ]; then
  sed -i '/redis/d' ./Procfile || true
  sed -i '/watch/d' ./Procfile || true
fi

# Pull CRM app and create your site
"${BENCH}" get-app crm

"${BENCH}" new-site "${HOSTNAME:-crm.localhost}" \
  --force \
  --mariadb-root-password "${MARIADB_ROOT_PASSWORD:-changeme}" \
  --admin-password "${SITE_ADMIN_PASSWORD:-changeme}" \
  --no-mariadb-socket

# Install + set defaults
"${BENCH}" --site "${HOSTNAME:-crm.localhost}" install-app crm
"${BENCH}" --site "${HOSTNAME:-crm.localhost}" set-config developer_mode 1
"${BENCH}" --site "${HOSTNAME:-crm.localhost}" clear-cache
"${BENCH}" use "${HOSTNAME:-crm.localhost}"

# Run forever
exec "${BENCH}" start