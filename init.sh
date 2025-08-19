#!/bin/bash
set -euo pipefail

# Expect these to be provided by Railway env:
# SITE_NAME, ADMIN_PASSWORD
# MYSQLHOST, MYSQLPORT, MYSQLUSER, MYSQLPASSWORD, MYSQLDATABASE  (from Railway MySQL)
# REDISHOST, REDISPORT, REDISPASSWORD                            (from Railway Redis)

export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"

SITE_NAME="${SITE_NAME:-crm.localhost}"

# Compose Redis URLs from envs
REDIS_URL="redis://:${REDISPASSWORD}@${REDISHOST}:${REDISPORT}"

# If bench already exists, just start
if [ -d "/home/frappe/frappe-bench/apps/frappe" ]; then
  echo "Bench already exists, starting..."
  cd /home/frappe/frappe-bench
  exec bench start
fi

echo "Creating new bench…"
cd /home/frappe
bench init --skip-redis-config-generation frappe-bench
cd frappe-bench

# Point to external MariaDB & Redis (Railway services)
bench set-mariadb-host "${MYSQLHOST}"
bench set-redis-cache-host    "${REDIS_URL}"
bench set-redis-queue-host    "${REDIS_URL}"
bench set-redis-socketio-host "${REDIS_URL}"

# Tweak Procfile – we won’t run Railway Redis processes
sed -i '/redis/d' ./Procfile
sed -i '/watch/d' ./Procfile

# Get your app and create the site
bench get-app crm
bench new-site "${SITE_NAME}" \
  --force \
  --mariadb-root-password "${MYSQLPASSWORD}" \
  --admin-password "${ADMIN_PASSWORD:-admin}" \
  --db-name "${MYSQLDATABASE}" \
  --db-host "${MYSQLHOST}" \
  --db-port "${MYSQLPORT}" \
  --db-user "${MYSQLUSER}" \
  --db-password "${MYSQLPASSWORD}" \
  --no-mariadb-socket

bench --site "${SITE_NAME}" install-app crm
bench --site "${SITE_NAME}" set-config developer_mode 1
bench --site "${SITE_NAME}" clear-cache
bench use "${SITE_NAME}"

# Start dev-style (single container) processes
exec bench start
