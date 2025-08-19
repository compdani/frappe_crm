FROM frappe/bench:v5.25.9
ENV SHELL=/bin/bash NODE_VERSION_DEVELOP=18 NVM_DIR=/home/frappe/.nvm
COPY init.sh /workspace/init.sh