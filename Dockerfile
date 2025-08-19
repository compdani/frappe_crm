# Use the official bench image
FROM frappe/bench:v5.25.9

# Runtime envs you asked to keep
ENV SHELL=/bin/bash \
    NODE_VERSION_DEVELOP=18 \
    NVM_DIR=/home/frappe/.nvm

# Copy our init script
COPY init.sh /workspace/init.sh
RUN chmod +x /workspace/init.sh

# Railway will execute this as the start command (see railway.json)
CMD ["bash", "/workspace/init.sh"]