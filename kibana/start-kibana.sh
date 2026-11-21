#!/bin/bash
# Get a service account token for Kibana, retrying until Elasticsearch is ready.
# A fixed token name is replaced on every start, so tokens do not pile up.
ES=http://elasticsearch:9200
AUTH="elastic:${ELASTIC_PASSWORD}"
TOKEN_URL="$ES/_security/service/elastic/kibana/credential/token/kibana-monitoring"

while true; do
    ELASTIC_TOKEN=$(curl -sf -u "$AUTH" -X POST "$TOKEN_URL" | jq -r '.token.value // empty')
    [ -n "$ELASTIC_TOKEN" ] && break
    echo "Waiting for Elasticsearch..."
    curl -sf -u "$AUTH" -X DELETE "$TOKEN_URL" >/dev/null 2>&1
    sleep 5
done
echo "Got Elasticsearch service token"
export ELASTIC_TOKEN
exec /usr/share/kibana/bin/kibana
