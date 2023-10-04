#!/bin/bash
sleep 50
export ELASTIC_TOKEN=$(curl -XPOST elasticsearch:9200/_security/service/elastic/kibana/credential/token -u elastic:${ELASTIC_PASSWORD} | jq -r '.token.value')
/usr/share/kibana/bin/kibana
