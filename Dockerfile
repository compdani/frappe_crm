FROM frappe/bench:v5.25.9

# Ensure we can create a safe entrypoint directory
USER root
RUN mkdir -p /opt/entrypoint && chown -R frappe:frappe /opt/entrypoint

# Run as frappe (bench user)
USER frappe

# Bench PATH + your envs
ENV SHELL=/bin/bash \
    NODE_VERSION_DEVELOP=18 \
    NVM_DIR=/home/frappe/.nvm \
    PATH=/home/frappe/.local/bin:/usr/local/bin:/usr/bin:/bin

# Embed the init script directly into the image (won't be hidden by volumes)
RUN cat > /opt/entrypoint/init.sh <<'EOF'
#!/bin/bash
set -euo pipefail

# Make sure bench is resolvable
export PATH="$HOME/.local/bin:$PATH"
if ! command -v bench >/dev/null 2>&1; then
  echo "bench not found on PATH: $PATH"
  if [ -x "/usr/local/bin/bench" ]; then
    mkdir -p "$HOME/.local/bin"
    ln -sf /usr/local/bin/bench "$HOME/.local/bin/bench"
  fi
fi

# Expect Railway envs:
# SITE_NAME, ADMIN_PASSWORD
# MYSQLHOST, MYSQLPORT, MYSQLUSER, MYSQLPASSWORD, MYSQLDATABASE
# REDISHOST, REDISPORT, REDISPASSWORD

export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"
SITE_NAME="${SITE_NAME:-crm.localhost}"
REDIS_URL="redis://:${REDISPASSWORD}@${REDISHOST}:${REDISPORT}"

# If bench already exists, start it
if [ -d "/home/frappe/frappe-bench/apps/frappe" ]; then
  echo "Bench already exists, starting…"
  cd /home/frappe/frappe-bench
  exec bench start
fi

echo "Creating new bench…"
cd /home/frappe
bench init --skip-redis-config-generation frappe-bench
cd frappe-bench

bench set-mariadb-host "${MYSQLHOST}"
bench set-redis-cache-host    "${REDIS_URL}"
bench set-redis-queue-host    "${REDIS_URL}"
bench set-redis-socketio-host "${REDIS_URL}"

# Don’t run redis/watch within this container
sed -i '/redis/d' ./Procfile || true
sed -i '/watch/d' ./Procfile || true

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

exec bench start
EOF

# Make sure it’s executable (owned by frappe already)
RUN chmod +x /opt/entrypoint/init.sh

# Login-like shell so any image profile hooks can extend PATH
CMD ["bash", "-lc", "/opt/entrypoint/init.sh"]