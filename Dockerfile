FROM frappe/bench:v5.25.9

ENV SHELL=/bin/bash \
    NODE_VERSION_DEVELOP=18 \
    NVM_DIR=/home/frappe/.nvm

# Put the script under the frappe home
COPY init.sh /workspace/init.sh

# No chmod needed — we'll run it with bash
CMD ["bash", "/workspace/init.sh"]