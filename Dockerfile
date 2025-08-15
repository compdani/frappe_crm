FROM python:3.11-alpine

RUN apk add --no-cache docker-cli docker-cli-compose bash curl git su-exec

WORKDIR /work
ENV HOME=/work

# Put the script where it won't be masked by the /work volume
COPY easy-install.py /usr/local/bin/easy-install.py

# Tiny entrypoint that fixes perms then drops privileges
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
