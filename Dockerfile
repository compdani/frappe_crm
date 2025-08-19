FROM frappe/bench:v5.25.9

ENV SHELL=/bin/bash \
    NODE_VERSION_DEVELOP=18 \
    NVM_DIR=/home/frappe/.nvm

# Put the script under the frappe home
COPY --chown=frappe:frappe init.sh /home/frappe/init.sh

# No chmod needed — we'll run it with bash
CMD ["bash", "/home/frappe/init.sh"]