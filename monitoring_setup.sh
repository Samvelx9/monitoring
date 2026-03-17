#!/bin/bash

set -e

echo "Creating directories..."

mkdir -p /data/{elasticsearch,prometheus,postgres}

echo "Setting permissions..."

chown -R 65534:65534 /data/prometheus
chmod -R 755 /data/prometheus

chown -R 1000:1000 /data/elasticsearch
chmod -R 755 /data/elasticsearch

chown -R 999:999 /data/postgres
chmod -R 700 /data/postgres

chown -R 472:472 ./grafana
chmod -R 755 ./grafana

echo ""
read -p "Do you want to run 'docker compose up -d'? (y/n): " answer

case "$answer" in
    [Yy]|[Yy][Ee][Ss])
        echo "Starting docker compose..."
        docker compose up -d
        ;;
    *)
        echo "Skipping docker compose."
        ;;
esac
