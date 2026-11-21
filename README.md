# Monitoring Setup

Installs Grafana, Prometheus, Elasticsearch, Logstash, Filebeat and Kibana with Docker on one Ubuntu server (22.04 / 24.04).

Requirements: 4 CPU, 16 GB RAM, 100 GB free disk, root access, internet.

How the setup works (architecture, configuration, logs, alerts, operations): [docs/MONITORING.md](docs/MONITORING.md).

Run the commands in order. Copy each block, paste it, and press Enter.

---

## 1. Become root

```bash
sudo -i
```

## 2. Install packages and Docker

```bash
apt-get update
apt-get install -y git nfs-common curl ca-certificates gettext-base
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
docker compose version
```

The last command must print `Docker Compose version v2...`.

## 3. Mount the logs from NFS

Replace `10.0.0.20:/applogs` with your NFS server IP and logs folder:

```bash
NFS='10.0.0.20:/applogs'
mkdir -p /applogs
echo "$NFS  /applogs  nfs  defaults,_netdev,ro  0  0" >> /etc/fstab
mount -a
ls /applogs
```

`ls` must show the environment folders. Log files must use this layout:
`/applogs/<environment>/<service>/<version>/logs/<file>.log`

## 4. Download the project

```bash
git clone https://github.com/Samvelx9/monitoring.git /opt/monitoring
cd /opt/monitoring
```

## 5. Fill in `.env`

```bash
nano /opt/monitoring/.env
```

Fill in every value marked `REQUIRED`. Keep the single quotes. Save with **Ctrl+O**, **Enter**, **Ctrl+X**.

To find `ELASTICSEARCH_NODEPORT`, run this on the Kubernetes master and take the number after `9200:`:

```bash
kubectl get svc -A | grep -i elastic
```

## 6. Install Prometheus in Kubernetes

The monitoring server reads all Kubernetes metrics from a second Prometheus that runs inside Kubernetes on NodePort `30900`. Run this on the Kubernetes master:

```bash
helm upgrade -i prometheus oci://registry.synisys.com/infrastructure/prometheus --version=16.0.2 --set alertmanager.enabled=false --set server.service.type=NodePort --set server.service.nodePort=30900 --set server.persistentVolume.enabled=false --namespace=monitoring --create-namespace
```

Check that it answers:

```bash
curl -s http://localhost:30900/-/ready
```

## 7. Install node-exporter on the other VMs

Skip this step if `SERVERS` in `.env` is empty. Otherwise run this on **each VM** listed there:

```bash
sudo apt-get update && sudo apt-get install -y prometheus-node-exporter
sudo systemctl enable --now prometheus-node-exporter
```

## 8. Run the setup

```bash
cd /opt/monitoring
bash monitoring_setup.sh
```

The script checks `.env`, generates the config files, starts all containers, waits until they are ready, sets the Grafana password, creates the Kibana data views and opens the firewall ports. The first run takes 5–15 minutes.

When it finishes, all lines should be green `[ OK ]` and the script prints the links.

## 9. Open

| | URL | User | Password |
|---|---|---|---|
| Grafana | `http://<MONITORING_IP>:3000` | `administrator` | `GRAFANA_ADMIN_PASSWORD` from `.env` |
| Kibana | `http://<MONITORING_IP>:5601` | `elastic` | `ELASTIC_PASSWORD` from `.env` |
| Prometheus | `http://<MONITORING_IP>:9090/targets` | – | – |

- **Grafana:** open **Dashboards → core_dashboards → Node Exporter Full**.
- **Kibana:** open **☰ → Discover**, choose the `logstash` data view, and set the time to **Last 15 minutes**.
- **Prometheus:** every target should be **UP**.

Done.

---

## Change settings later

Edit `.env` and run the script again. It is safe to run many times.

```bash
cd /opt/monitoring
nano .env
bash monitoring_setup.sh
```

This works for every value except `ELASTIC_PASSWORD` and `POSTGRES_PASSWORD`. Change those two as shown below.

### Change `ELASTIC_PASSWORD`

Set the new password in Elasticsearch first (letters and numbers only):

```bash
cd /opt/monitoring
source .env
NEW_PASSWORD='NewPassword123'
curl -s -u "elastic:$ELASTIC_PASSWORD" -X POST localhost:9200/_security/user/elastic/_password \
  -H 'Content-Type: application/json' -d "{\"password\":\"$NEW_PASSWORD\"}"
```

The output must be `{}`. Then write the same new password into `ELASTIC_PASSWORD` in `.env` and run the script:

```bash
nano .env
bash monitoring_setup.sh
```

### Change `POSTGRES_PASSWORD`

Set the new password in PostgreSQL first (letters and numbers only):

```bash
cd /opt/monitoring
NEW_PASSWORD='NewPassword123'
docker compose exec -T postgres psql -U grafana -d grafana -c "ALTER USER grafana WITH PASSWORD '$NEW_PASSWORD';"
```

The output must be `ALTER ROLE`. Then write the same new password into `POSTGRES_PASSWORD` in `.env` and run the script:

```bash
nano .env
bash monitoring_setup.sh
```

## Optional: nginx logs

Add these lines to the `http { }` block of the nginx config on the nginx VM, then reload nginx:

```nginx
access_log syslog:server=<MONITORING_IP>:5045,tag=nginx_access main;
error_log  syslog:server=<MONITORING_IP>:5046,tag=nginx_error;
```

`main` is the name of the `log_format` already defined in the standard nginx config. Logstash can only read that format (see `NGINXACCESS` in `logstash/patterns/nginxlogs/nginx`). Don't use nginx's default `combined` format.

## Ports

| Port | Service |
|---|---|
| 3000 | Grafana |
| 5601 | Kibana |
| 9090 | Prometheus |
| 9200, 9300 | Elasticsearch |
| 5044 | Logstash (beats) |
| 5045 tcp/udp | Logstash (nginx access syslog) |
| 5046 tcp/udp | Logstash (nginx error syslog) |
| 5432 | PostgreSQL (Grafana DB) |
| 9100 | node-exporter |
| 8080 | cAdvisor |
| 9114, 9115 | Elasticsearch exporters |

## Files

| Path | Content |
|---|---|
| `.env` | all settings |
| `monitoring_setup.sh` | setup script |
| `templates/` | source for generated `prometheus/prometheus.yml`, Grafana contact points and Elasticsearch data source (don't edit the generated files) |
| `/data/elasticsearch` | Elasticsearch data |
| `/data/prometheus` | Prometheus data |
| `/data/postgres` | Grafana database |
| `/applogs` | application logs (NFS, read-only) |

## No internet on the server

On a machine with internet and Docker:

```bash
IMAGES="prom/node-exporter:v1.3.1 prometheuscommunity/elasticsearch-exporter:v1.5.0 woodliu268/cadvisor:v0.43.0 grafana/grafana:12.3.3 prom/prometheus:v3.9.1 postgres:18.2 docker.elastic.co/elasticsearch/elasticsearch:8.9.1 docker.elastic.co/beats/filebeat:8.9.1 docker.elastic.co/logstash/logstash:8.9.1 docker.elastic.co/kibana/kibana:8.9.1"
for i in $IMAGES; do docker pull "$i"; done
docker save -o monitoring-images.tar $IMAGES
```

Copy `monitoring-images.tar` to the server, then run:

```bash
docker load -i monitoring-images.tar
```

The Kibana build runs `apt-get install jq`, which needs internet. Build that image on the online machine with `docker compose build kibana`, then save and load it the same way.
