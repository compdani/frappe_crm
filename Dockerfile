FROM frappe/bench:v5.25.9

ENV SHELL=/bin/bash \
    NODE_VERSION_DEVELOP=18 \
    NVM_DIR=/home/frappe/.nvm

# Ensure /workspace exists and file is readable by the app user at build time
USER root
RUN mkdir -p /workspace && chown -R frappe:frappe /workspace
COPY --chown=frappe:frappe init.sh /workspace/init.sh
# read-only is enough because we'll run it via bash
RUN chmod 0644 /workspace/init.sh
USER frappe