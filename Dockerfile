# Minimal image with Python + Docker CLI + compose plugin
FROM python:3.11-alpine

RUN apk add --no-cache docker-cli docker-cli-compose bash curl git

WORKDIR /work
ENV HOME=/work

# copy the script into the image (or mount it at runtime instead)
COPY easy-install.py /work/easy-install.py

ENTRYPOINT ["python3", "/work/easy-install.py"]
