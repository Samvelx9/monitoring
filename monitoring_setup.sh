#!/bin/bash
# Sets up and starts the whole monitoring stack using the values from .env.
# Usage: sudo bash monitoring_setup.sh   (safe to run again)

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

ok()   { echo -e "\e[32m[ OK ]\e[0m $*"; }
info() { echo -e "\e[34m[....]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
fail() { echo -e "\e[31m[FAIL]\e[0m $*"; exit 1; }

wait_for() { # wait_for <name> <timeout_seconds> <command...>
    local name=$1 timeout=$2; shift 2
    local start=$SECONDS
    info "Waiting for $name..."
    until "$@" >/dev/null 2>&1; do
        (( SECONDS - start > timeout )) && fail "$name is not ready after ${timeout}s. Check: docker compose logs --tail=50 $name"
        sleep 10
    done
    ok "$name is ready"
}

# ---------------------------------------------------------------- checks
[ "$(id -u)" -eq 0 ] || fail "Run as root: sudo bash monitoring_setup.sh"
command -v docker >/dev/null || fail "Docker is not installed (README step 2)"
docker compose version >/dev/null 2>&1 || fail "'docker compose' plugin is missing (README step 2)"
command -v envsubst >/dev/null || fail "envsubst is missing: apt-get install -y gettext-base"
[ -f .env ] || fail ".env file not found"

set -a; source ./.env; set +a

missing=()
for v in MONITORING_IP KUBEMASTER_IP ELASTICSEARCH_NODEPORT ELASTIC_PASSWORD GRAFANA_ADMIN_PASSWORD \
         POSTGRES_PASSWORD TEAMS_WEBHOOK ALERT_EMAIL SMTP_HOST SMTP_USER SMTP_PASSWORD; do
    [ -n "${!v:-}" ] || missing+=("$v")
done
[ ${#missing[@]} -eq 0 ] || fail "Fill in these values in .env: ${missing[*]}"
[[ "$ELASTIC_PASSWORD" =~ ^[A-Za-z0-9]+$ ]]  || fail "ELASTIC_PASSWORD must contain only letters and numbers"
[[ "$POSTGRES_PASSWORD" =~ ^[A-Za-z0-9]+$ ]] || fail "POSTGRES_PASSWORD must contain only letters and numbers"
ok ".env is filled in"

if [ -d /applogs ] && [ -n "$(ls -A /applogs 2>/dev/null)" ]; then
    ok "/applogs has content"
else
    warn "/applogs is missing or empty - application logs will not appear in Kibana (README step 3)"
    mkdir -p /applogs
fi

# ---------------------------------------------------------------- host settings
if [ "$(sysctl -n vm.max_map_count)" -lt 262144 ]; then
    info "Setting vm.max_map_count for Elasticsearch"
    sysctl -qw vm.max_map_count=262144
    echo 'vm.max_map_count=262144' > /etc/sysctl.d/99-elasticsearch.conf
fi

info "Creating data folders"
mkdir -p /data/{elasticsearch,prometheus,postgres}
chown -R 1000:1000   /data/elasticsearch && chmod 755 /data/elasticsearch
chown -R 65534:65534 /data/prometheus    && chmod 755 /data/prometheus
chown -R 999:999     /data/postgres      && chmod 700 /data/postgres
ok "Data folders ready"

# ---------------------------------------------------------------- config files
info "Generating config files from templates/"
SERVER_TARGETS=""
for s in ${SERVERS:-}; do
    SERVER_TARGETS+="      - targets: ['${s%%:*}:9100']"$'\n'"        labels:"$'\n'"          service: \"${s#*:}\""$'\n'
done
export SERVER_TARGETS="${SERVER_TARGETS%$'\n'}"

mkdir -p prometheus
envsubst '${KUBEMASTER_IP} ${SERVER_TARGETS}' < templates/prometheus.yml               > prometheus/prometheus.yml
envsubst '${TEAMS_WEBHOOK} ${ALERT_EMAIL}'    < templates/contactpoints.yml            > grafana/provisioning/alerting/contactpoints.yml
envsubst '${ELASTIC_PASSWORD}'                < templates/elasticsearch-datasource.yml > grafana/provisioning/datasources/elasticsearch.yml

chown -R 472:472 ./grafana && chmod -R 755 ./grafana/provisioning
ok "Config files generated"

# ---------------------------------------------------------------- start
info "Starting containers (first time takes 5-15 minutes)"
docker compose up -d --build
docker compose restart grafana prometheus >/dev/null   # load freshly generated configs

wait_for elasticsearch 600 sh -c "curl -s -u 'elastic:${ELASTIC_PASSWORD}' localhost:9200/_cluster/health | grep -qE '\"status\":\"(green|yellow)\"'"
wait_for grafana       300 sh -c "curl -s localhost:3000/api/health | grep -q '\"database\": *\"ok\"'"
wait_for kibana        600 sh -c "curl -s -u 'elastic:${ELASTIC_PASSWORD}' localhost:5601/api/status | grep -q '\"level\":\"available\"'"
wait_for prometheus    120 sh -c "curl -s localhost:9090/-/ready"

# ---------------------------------------------------------------- final setup
info "Setting Grafana admin password"
docker compose exec -T grafana grafana cli admin reset-admin-password "$GRAFANA_ADMIN_PASSWORD" >/dev/null
ok "Grafana admin password set"

info "Creating Kibana data views"
existing=$(curl -s -u "elastic:${ELASTIC_PASSWORD}" localhost:5601/api/data_views)
for dv in logstash nginx-access nginx-error; do
    if echo "$existing" | grep -q "\"title\":\"${dv}\*\""; then
        ok "Data view ${dv}* already exists"
    else
        curl -sf -u "elastic:${ELASTIC_PASSWORD}" -X POST localhost:5601/api/data_views/data_view \
            -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
            -d "{\"data_view\":{\"name\":\"${dv}\",\"title\":\"${dv}*\",\"timeFieldName\":\"@timestamp\"}}" >/dev/null \
            && ok "Data view ${dv}* created" || warn "Could not create data view ${dv}*"
    fi
done

if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
    info "Opening firewall ports"
    for p in 3000/tcp 5601/tcp 9090/tcp 5044/tcp 5045 5046; do ufw allow "$p" >/dev/null; done
    ok "Firewall ports opened"
fi

# ---------------------------------------------------------------- report
for s in ${SERVERS:-}; do
    ip=${s%%:*}
    if curl -s -m 5 -o /dev/null "http://${ip}:9100/metrics"; then ok "node-exporter on ${ip} answers"
    else warn "node-exporter on ${ip} does not answer on port 9100 (README step 7)"; fi
done
curl -s -m 5 -o /dev/null "http://${KUBEMASTER_IP}:30900/-/ready" && ok "Kubernetes Prometheus answers" \
    || warn "Kubernetes Prometheus does not answer on ${KUBEMASTER_IP}:30900 (README step 6)"

echo
docker compose ps --format 'table {{.Name}}\t{{.Status}}'
echo
echo "=============================================================="
echo " Grafana:    http://${MONITORING_IP}:3000   user: administrator"
echo " Kibana:     http://${MONITORING_IP}:5601   user: elastic"
echo " Prometheus: http://${MONITORING_IP}:9090/targets"
echo " Passwords are in /opt/monitoring/.env"
echo "=============================================================="
