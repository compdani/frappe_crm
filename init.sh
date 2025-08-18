#!/bin/bash
set -euo pipefail

# ---- defaults (override via env)
: "${BENCH_DIR:=/home/frappe/frappe-bench}"
: "${BENCH_CMD:=/home/frappe/.local/bin/bench}"
: "${HOSTNAME:=crm.localhost}"
: "${SQL_URL:=}"
: "${REDIS_URL:=}"
: "${NVM_DIR:=/home/frappe/.nvm}"
: "${NODE_VERSION_DEVELOP:=}"   # optional

# 0) If volume mounted BENCH_DIR is owned by root, fix perms so 'frappe' can write
if [ -d "$BENCH_DIR" ]; then
  owner="$(stat -c '%U:%G' "$BENCH_DIR" 2>/dev/null || echo '')"
  if [ "$owner" != "frappe:frappe" ]; then
    echo "Fixing ownership of ${BENCH_DIR} -> frappe:frappe"
    chown -R frappe:frappe "$BENCH_DIR"
  fi
fi

# 1) Always run as 'frappe' under a bash login shell
if [ "$(id -un)" != "frappe" ]; then
  exec su -s /bin/bash -l frappe -c "bash -lc '/workspace/init.sh'"
fi

# 2) Minimal PATH; no pyenv dependency
export HOME="/home/frappe"
export PATH="/home/frappe/.local/bin:/usr/local/bin:/usr/bin:/bin"
# Optional Node paths, only if present
if [ -n "${NODE_VERSION_DEVELOP}" ] && [ -d "${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin" ]; then
  export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin:${PATH}"
fi
if [ -d "${NVM_DIR}/versions/node/v20.19.2/bin" ]; then
  export PATH="${NVM_DIR}/versions/node/v20.19.2/bin:${PATH}"
fi

# 3) Resolve bench (pipx symlink or venv)
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
  echo "ERROR: bench not found."
  exit 1
fi

# 4) Detect "valid bench" markers
has_procfile=false
[ -f "${BENCH_DIR}/Procfile" ] && has_procfile=true
has_sites=false
[ -d "${BENCH_DIR}/sites" ] && has_sites=true
has_apps_frappe=false
[ -d "${BENCH_DIR}/apps/frappe" ] && has_apps_frappe=true

# If directory exists but is not a valid bench, seed it from a temp init
if [ -d "${BENCH_DIR}" ] && { [ "${has_procfile}" = false ] || [ "${has_sites}" = false ]; }; then
  echo "Seeding mounted bench directory at ${BENCH_DIR} (no Procfile and/or sites)..."
  SEED="/home/frappe/.bench_seed"
  rm -rf "${SEED}"
  "${BENCH}" init --skip-redis-config-generation "${SEED}"
  # copy seed bench into BENCH_DIR
  shopt -s dotglob
  cp -a "${SEED}/"* "${BENCH_DIR}/"
  rm -rf "${SEED}"
  has_procfile=true
  has_sites=true
fi

# If completely fresh (no apps/frappe), initialize bench at BENCH_DIR
if [ "${has_apps_frappe}" = false ]; then
  # If BENCH_DIR didn't exist, create it via init
  if [ ! -d "${BENCH_DIR}/apps" ]; then
    echo "Creating new bench at ${BENCH_DIR}..."
    # 'bench init' errors if path exists-but-nonempty; we handled that above by seeding/copying
    # so this branch runs only when directory is missing entirely
    "${BENCH}" init --skip-redis-config-generation "${BENCH_DIR}"
    has_procfile=true
    has_sites=true
  fi
fi

# From here on, always operate inside the bench dir
cd "${BENCH_DIR}"

# 5) Configure external services -> writes ./sites/common_site_config.json
#    (Common site config is the bench-level config store.)  docs: https://docs.frappe.io/framework/user/en/basics/site_config
if [ ! -d "./sites" ]; then
  echo "ERROR: ${BENCH_DIR}/sites does not exist after seeding; invalid bench."
  exit 1
fi

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

# 6) Clean Procfile only if present
if [ -f "./Procfile" ]; then
  sed -i '/redis/d' ./Procfile || true
  sed -i '/watch/d' ./Procfile || true
fi

# 7) Get CRM app if missing; create site if missing
[ -d "apps/crm" ] || "${BENCH}" get-app crm

SITE="${HOSTNAME}"
SITE_DIR="${BENCH_DIR}/sites/${SITE}"
if [ ! -d "${SITE_DIR}" ]; then
  echo "Creating site ${SITE}..."
  "${BENCH}" new-site "${SITE}" \
    --force \
    --mariadb-root-password "${MARIADB_ROOT_PASSWORD}" \
    --admin-password "${SITE_ADMIN_PASSWORD}" \
    --no-mariadb-socket"
fi

"${BENCH}" --site "${SITE}" install-app crm
"${BENCH}" --site "${SITE}" set-config developer_mode 1
"${BENCH}" --site "${SITE}" clear-cache
"${BENCH}" use "${SITE}"

exec "${BENCH}" start