FROM frappe/bench:v5.25.9

ENV DEBIAN_FRONTEND=noninteractive \
    SHELL=/bin/bash \
    HOSTNAME=crm.localhost \
    MARIADB_ROOT_PASSWORD=changeme \
    SITE_ADMIN_PASSWORD=changeme \
    SQL_URL=changeme \
    REDIS_URL=changeme \
    HOME=/home/frappe \
    BENCH_CMD=/home/frappe/.local/bin/bench \
    BENCH_DIR=/home/frappe/frappe-bench

# Install venv so `bench init` can create its Python env
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3.11-venv \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /workspace && chown -R frappe:frappe /workspace
WORKDIR /workspace

COPY init.sh /workspace/init.sh
RUN chmod +x /workspace/init.sh

EXPOSE 8000

# Run as root; script will su->frappe with a login bash
CMD ["/bin/bash", "-lc", "/workspace/init.sh"]