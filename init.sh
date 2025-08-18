#!/usr/bin/env bash
set -euo pipefail

# Defaults (override via ENV if desired)
: "${BENCH_DIR:=/home/frappe/frappe-bench}"
: "${BENCH_CMD:=/home/frappe/.local/bin/bench}"
: "${HOSTNAME:=crm.localhost}"
: "${SQL_URL:=}"
: "${REDIS_URL:=}"
: "${NVM_DIR:=/home/frappe/.nvm}"
: "${NODE_VERSION_DEVELOP:=}"  # optional, for Node path

# 1) Fix ownership if volume-mounted directory is owned by root
if [ -d "${BENCH_DIR}" ] && [ "$(stat -c '%U:%G' "${BENCH_DIR}")" != "frappe:frappe" ]; then
  echo "Fixing ownership of ${BENCH_DIR} to frappe:frappe"
  chown -R frappe:frappe "${BENCH_DIR}"
fi

# 2) Re-exec as 'frappe' user under bash login shell to get correct path & env
if [ "$(id -un)" != "frappe" ]; then
  exec su -s /bin/bash -l frappe -c "bash -lc '/workspace/init.sh'"
fi

# 3) Clean PATH environment and include bench command
export HOME=/home/frappe
export PATH="/home/frappe/.local/bin:/usr/local/bin:/usr/bin:/bin"

# Optional: prepend Node path if specified and present
if [ -n "${NODE_VERSION_DEVELOP}" ] && [ -d "${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin" ]; then
  export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin:${PATH}"
fi

# 4) Locate bench executable (pipx venv or fallback)
CANDS=(
  "${BENCH_CMD}"
  "/home/frappe/.local/bin/bench"
  "/home/frappe/.local/share/pipx/venvs/bench/bin/bench"
  "/home/frappe/.local/pipx/venvs/bench/bin/bench"
)
BENCH=""
for c in "${CANDS[@]}"; do
  if [ -x "$c" ]; then
    BENCH="$c"
    break
  fi
done
[ -z "$BENCH" ] && BENCH="$(command -v bench || true)"
if [ -z "$BENCH" ]; then
  echo "ERROR: bench not found. Searched paths:" "${CANDS[@]}"
  exit 1
fi

# 5) Check if the bench directory exists and is valid
procfile_exists=false
[ -f "${BENCH_DIR}/Procfile" ] && procfile_exists=true
apps_exists=false
[ -d "${BENCH_DIR}/apps/frappe" ] && apps_exists=true
sites_exists=false
[ -d "${BENCH_DIR}/sites" ] && sites_exists=true

# 6) If bench dir exists but isn't valid, seed it
if [ -d "${BENCH_DIR}" ] && (! $procfile_exists || ! $apps_exists); then
  echo "Seeding incomplete bench directory at ${BENCH_DIR}"
  SEED="/home/frappe/.bench_seed"
  rm -rf "${SEED}"
  "${BENCH}" init --skip-redis-config-generation "${SEED}"
  shopt -s dotglob
  cp -a "${SEED}/"* "${BENCH_DIR}/"
  rm -rf "${SEED}"
fi

# 7) If bench directory doesn't exist at all, initialize it
if [ ! -d "${BENCH_DIR}/apps" ]; then
  echo "Initializing new bench at ${BENCH_DIR}"
  "${BENCH}" init --skip-redis-config-generation "${BENCH_DIR}"
fi

cd "${BENCH_DIR}"

# 8) Configure external services (writes common_site_config.json)
if [ -n "${SQL_URL}" ] && [ "${SQL_URL}" != "changeme" ]; then
  if "${BENCH}" --help | grep -q "set-mariadb-host"; then
    "${BENCH}" set-mariadb-host "${SQL_URL}"
  else
    "${BENCH}" set-config -g db_host "${SQL_URL}"
  fi
fi
if [ -n "${REDIS_URL}" ] && [ "${REDIS_URL}" != "changeme" ]; then
  "${BENCH}" set-redis-cache-host    "${REDIS_URL}"
  "${BENCH}" set-redis-queue-host    "${REDIS_URL}"
  "${BENCH}" set-redis-socketio-host "${REDIS_URL}"
fi

# 9) Clean Procfile’s redis/watch lines if it exists
[ -f "./Procfile" ] && sed -i '/redis\|watch/d' ./Procfile || true

# 10) Install or reinstall CRM app
[ -d "apps/crm" ] || "${BENCH}" get-app crm

# 11) Create site if missing, then install and configure
SITE_DIR="${BENCH_DIR}/sites/${HOSTNAME}"
if [ ! -d "${SITE_DIR}" ]; then
  echo "Creating new site: ${HOSTNAME}"
  "${BENCH}" new-site "${HOSTNAME}" \
    --force \
    --mariadb-root-password "${MARIADB_ROOT_PASSWORD}" \
    --admin-password "${SITE_ADMIN_PASSWORD}" \
    --no-mariadb-socket
fi

"${BENCH}" --site "${HOSTNAME}" install-app crm
"${BENCH}" --site "${HOSTNAME}" set-config developer_mode 1
"${BENCH}" --site "${HOSTNAME}" clear-cache
"${BENCH}" use "${HOSTNAME}"

# 12) Finally, start bench
exec "${BENCH}" start