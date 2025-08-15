FROM python:3.11-alpine

RUN apk add --no-cache docker-cli docker-cli-compose bash curl git

# We'll still use /work as the writable working area
WORKDIR /work
ENV HOME=/work

# Put the script somewhere that won't be masked by the /work volume
COPY easy-install.py /usr/local/bin/easy-install.py

ENTRYPOINT ["python3", "/usr/local/bin/easy-install.py"]
