#!/bin/bash
set -euo pipefail

# ---- sane defaults so `set -u` is happy (override via ENV if you want)
: "${BENCH_DIR:=/home/frappe/frappe-bench}"
: "${BENCH_CMD:=/home/frappe/.local/bin/bench}"
: "${HOSTNAME:=crm.localhost}"
: "${SQL_URL:=}"
: "${REDIS_URL:=}"
# We won't force a specific Node; use it only if present
: "${NVM_DIR:=/home/frappe/.nvm}"
: "${NODE_VERSION_DEVELOP:=}"   # optional

# 0) Fix ownership if a volume mounted the bench dir as root
if [ -d "$BENCH_DIR" ]; then
  owner="$(stat -c '%U:%G' "$BENCH_DIR" 2>/dev/null || echo '')"
  if [ "$owner" != "frappe:frappe" ]; then
    echo "Fixing ownership of ${BENCH_DIR} -> frappe:frappe"
    chown -R frappe:frappe "$BENCH_DIR"
  fi
fi

# 1) Ensure we run as 'frappe' under a **bash login shell**
if [ "$(id -un)" != "frappe" ]; then
  exec su -s /bin/bash -l frappe -c "bash -lc '/workspace/init.sh'"
fi

# 2) Minimal PATH; avoid requiring pyenv
export HOME="/home/frappe"
export PATH="/home/frappe/.local/bin:/usr/local/bin:/usr/bin:/bin"

# (optional) add Node if that exact dir exists
if [ -n "${NODE_VERSION_DEVELOP}" ] && [ -d "${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin" ]; then
  export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin:${PATH}"
fi
# also add image’s default Node v20 if present
if [ -d "${NVM_DIR}/versions/node/v20.19.2/bin" ]; then
  export PATH="${NVM_DIR}/versions/node/v20.19.2/bin:${PATH}"
fi

# DO NOT source ~/.profile (often contains pyenv init -> breaks if pyenv missing)

# 3) Resolve bench robustly (pipx symlink or venv path)
CANDIDATES=(
  "${BENCH_CMD}"
  "/home/frappe/.local/bin/bench"
  "/home/frappe/.local/share/pipx/venvs/bench/bin/bench"
  "/home/frappe/.local/pipx/venvs/bench/bin/bench"
)
BENCH=""
for c in "${CANDIDATES[@]}"; do
  [ -x "$c" ] && BENCH="$c" && break
done
if [ -z "$BENCH" ] && command -v bench >/dev/null 2>&1; then
  BENCH="$(command -v bench)"
fi
if [ -z "$BENCH" ]; then
  echo "ERROR: bench not found; checked:"
  printf ' - %s\n' "${CANDIDATES[@]}"
  echo "PATH=$PATH"
  exit 1
fi

SITE="${HOSTNAME}"

# 4) Init bench only if missing; otherwise use existing
if [ ! -d "${BENCH_DIR}/apps/frappe" ]; then
  echo "Creating new bench at ${BENCH_DIR}..."
  "${BENCH}" init --skip-redis-config-generation "${BENCH_DIR}"
fi

# Always operate **inside** the bench dir
cd "${BENCH_DIR}"

# Ensure sites is writable (volume perms)
if [ ! -w "./sites" ]; then
  echo "ERROR: ${BENCH_DIR}/sites not writable by 'frappe' (volume perms?)."
  exit 1
fi

# 5) Configure external services (writes to sites/common_site_config.json)
if [ -n "${SQL_URL}" ] && [ "${SQL_URL}" != "changeme" ]; then
  if "${BENCH}" --help 2>/dev/null | grep -q "set-mariadb-host"; then
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

# 6) Clean Procfile (idempotent)
sed -i '/redis/d' ./Procfile || true
sed -i '/watch/d' ./Procfile || true

# 7) Get CRM app if missing; create site if missing
[ -d "apps/crm" ] || "${BENCH}" get-app crm

SITE_DIR="${BENCH_DIR}/sites/${SITE}"
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

# 8) Start bench (PID 1)
exec "${BENCH}" start