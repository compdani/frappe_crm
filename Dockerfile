# Dockerfile
FROM frappe/bench:v5.25.9

# Match your env (override at runtime if needed)
ENV SHELL=/bin/bash \
    NODE_VERSION_DEVELOP=18 \
    NVM_DIR=/home/frappe/.nvm \
    HOSTNAME=crm.localhost \
    MARIADB_ROOT_PASSWORD=changeme \
    SITE_ADMIN_PASSWORD=changeme \
    SQL_URL=changeme \
    REDIS_URL=changeme \
    HOME=/home/frappe \
    BENCH_CMD=/home/frappe/.local/bin/bench

USER root
RUN mkdir -p /workspace && chown -R frappe:frappe /workspace
WORKDIR /workspace

COPY init.sh /workspace/init.sh
RUN chmod +x /workspace/init.sh

# Bench web default
EXPOSE 8000

# Prefer running as frappe; if the platform forces root, init.sh re-execs as frappe
USER frappe
CMD ["bash", "-lc", "/workspace/init.sh"]
