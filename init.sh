#!/bin/bash
set -euo pipefail

if [ -d "/home/frappe/frappe-bench/apps/frappe" ]; then
    echo "Bench already exists, skipping init"
    cd frappe-bench
    bench start
    exit 0
else
    echo "Creating new bench..."
fi

# Ensure Node from nvm is on PATH
export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"

bench init --skip-redis-config-generation frappe-bench
cd frappe-bench

# Use containers instead of localhost
bench set-mariadb-host "${SQL_URL}"
bench set-redis-cache-host "${REDIS_URL}"
bench set-redis-queue-host "${REDIS_URL}"
bench set-redis-socketio-host "${REDIS_URL}"

# Remove redis, watch from Procfile
sed -i '/redis/d' ./Procfile
sed -i '/watch/d' ./Procfile

bench get-app crm

bench new-site crm.localhost \
  --force \
  --mariadb-root-password "${MARIADB_ROOT_PASSWORD}" \
  --admin-password "${SITE_ADMIN_PASSWORD}" \
  --no-mariadb-socket

bench --site crm.localhost install-app crm
bench --site crm.localhost set-config developer_mode 1
bench --site crm.localhost clear-cache
bench use crm.localhost

bench start
