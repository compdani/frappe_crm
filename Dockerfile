FROM frappe/bench:v5.25.9

ENV SHELL=/bin/bash \
    HOSTNAME=crm.localhost \
    MARIADB_ROOT_PASSWORD=changeme \
    SITE_ADMIN_PASSWORD=changeme \
    SQL_URL=changeme \
    REDIS_URL=changeme \
    HOME=/home/frappe \
    BENCH_CMD=/home/frappe/.local/bin/bench \
    BENCH_DIR=/home/frappe/frappe-bench

USER root
RUN mkdir -p /workspace && chown -R frappe:frappe /workspace
WORKDIR /workspace

COPY init.sh /workspace/init.sh
RUN chmod +x /workspace/init.sh

EXPOSE 8000

# run as root; init.sh will re-exec as 'frappe' via bash -l
CMD ["/bin/bash", "-lc", "/workspace/init.sh"]