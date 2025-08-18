#!bin/bash

if [ -d "/home/frappe/frappe-bench/apps/frappe" ]; 
then    echo "Bench already exists, skipping init"
  cd frappe-bench
  bench start
else
  echo "Creating new bench..."
fi

export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"
bench init --skip-redis-config-generation frappe-bench
cd frappe-bench
# Use containers instead of localhost
bench set-mariadb-host $(PROJECT_NAME)_frappe-crm-mariadb
bench set-redis-cache-host redis://:097f4533be1f5ee0f8ae@$(PROJECT_NAME)_frappe-crm-redis:6379
bench set-redis-queue-host redis://:097f4533be1f5ee0f8ae@$(PROJECT_NAME)_frappe-crm-redis:6379
bench set-redis-socketio-host redis://:097f4533be1f5ee0f8ae@$(PROJECT_NAME)_frappe-crm-redis:6379
# Remove redis, watch from Procfile
sed -i '/redis/d' ./Procfile
sed -i '/watch/d' ./Procfile
bench get-app crm
bench new-site crm.localhost --force --mariadb-root-password 582256ca08fdb6a5e434 --admin-password admin --no-mariadb-socket
bench --site crm.localhost install-app crm
bench --site crm.localhost set-config developer_mode 1
bench --site crm.localhost clear-cache
bench use crm.localhost
bench start
