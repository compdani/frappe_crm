#!/bin/bash
if [ -d "/home/frappe/frappe-bench/apps/frappe" ]; then
    echo "Bench already exists, skipping init"
    cd frappe-bench
    bench start
else
    echo "Creating new bench..."
fi
export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"

bench init --skip-redis-config-generation frappe-bench

cd frappe-bench

SITE_NAME="${SITE_NAME:-crm.localhost}"

# Build Redis URL (with or without password)
if [ -n "${REDISPASSWORD:-}" ]; then
  REDIS_URL="redis://:${REDISPASSWORD}@${REDISHOST}:${REDISPORT}"
else
  REDIS_URL="redis://${REDISHOST}:${REDISPORT}"
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

# Don’t run local redis/watch in this container
sed -i '/redis/d' ./Procfile || true
sed -i '/watch/d' ./Procfile || true

# Install your app and create the site
bench get-app crm

# For managed MySQL on Railway, the provided MYSQLUSER is your “admin” here.
# We pass it as the "mariadb root" user so bench can create the DB & user.
bench new-site "${SITE_NAME}" \
  --force \
  --mariadb-root-username "${MYSQLUSER}" \
  --mariadb-root-password "${MYSQLPASSWORD}" \
  --admin-password "${ADMIN_PASSWORD:-admin}" \
  --db-name "${MYSQLDATABASE}" \
  --db-host "${MYSQLHOST}" \
  --db-port "${MYSQLPORT}" \
  --db-user "${MYSQLUSER}" \
  --db-password "${MYSQLPASSWORD}" \
  --no-mariadb-socket

bench --site "${SITE_NAME}" install-app crm
bench --site "${SITE_NAME}" set-config developer_mode 0
bench --site "${SITE_NAME}" clear-cache
bench use "${SITE_NAME}"

# Start dev-style (single container) processes
exec bench start