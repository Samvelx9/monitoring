#################################################################### PREREQUIREMENTS ####################################################################

Before starting install process please asure: 
    1) You have all provided files downloaded on your MONITORING VM 
    2) You have internet access on MONITORING VM, or on other VM so you can download files and images to that VM and pass them  to MONITORING VM
    3) You have docker installed on MONITORING VM
    4) You have docker-compose installed on MONITORING VM
    5) If there is no outgoing internet access and there is no access to "registry.synisys.com/infrastructure" public repository, download following images, reatag and push them to your repository. Replace images in the "docker-compose.yml" file for exporters and cadvisor and in "Dockerfile" files for grafana, prometheus, elasticsearch, filebeat, logstash and kibana

    registry.synisys.com/infrastructure/node-exporter:v1.3.1
    registry.synisys.com/infrastructure/elasticsearch-exporter:v1.5.0
    registry.synisys.com/infrastructure/cadvisor:v0.43.0
    registry.synisys.com/infrastructure/grafana:12.3.3
    registry.synisys.com/infrastructure/prometheus:v3.9.1
    docker.elastic.co/elasticsearch/elasticsearch:8.9.1
    docker.elastic.co/beats/filebeat:8.9.1
    docker.elastic.co/logstash/logstash:8.9.1
    docker.elastic.co/kibana/kibana:8.9.1

    6) Create logs directory at "/applogs" path and mount logs into it

    7) Perform further steps mentioned in the instruction or just run monitoring_setup.sh script (bash monitoring_setup.sh)

########################################################## Elastic stack (ELK) setup on Docker ##########################################################

1) Edit ".env" file and set desired values for each field in the "ELK" section. 

    Following options have default values which will be used if you leave these fields empty:
    ELASTIC_MEMORY='1g'
    LOGSTASH_MEMORY='512m'

2) Create data folder for elasticsearch at "/data/elasticsearch" path and fix permissions

    mkdir -p /data/elasticsearch
    chown -R 1000:1000 /data/elasticsearch
    chmod -R 755 /data/elasticsearch

3) Create logs directory at "/applogs" path and mount logs into it

11) Create Kibana data view (Do this step after completing all other steps)

    1. Login into kibana (${monitoring_server_ip}:5601)
    2. Go to "Stack_Management" and go to "Data Views" in "Kibana" section
    3. Create new Data View with "logstash" name and "logstash*" index pattern, select "@timestamp" as Timestamp field and press "Save data view to Kibana"
    4. Go to Discover in Analytics section to assure logs are being loaded and kibana works normally





########################################################## Prometheus and Grafana setup on Docker ##########################################################

4) Edit .env file and set desired/required values for each field in the "PROMETHEUS AND GRAFANA" section.

    Following options have default values which will be used if you leave these fields empty:
    PROMETHEUS_RETENTION='200h'
    PROMETHEUS_MEMORY='3gb'

5) Create data folder for prometheus at "/data/prometheus" path and fix permissions

    mkdir -p /data/prometheus
    chown -R 65534:65534 /data/prometheus
    chmod -R 755 /data/prometheus

6) Change elastic user password in grafana datasource (./grafana/provisioning/datasources/elasticsearch.yml)

7) Edit grafana configs and change permissions

    1. Edit ./grafana/grafana.ini file
    2. configure "smtp" section with your mailserver credentials
    3. configure "server" section change "domain" from 0.0.0.0 to your monitoring server ip
    4. chown -R 472:472 ./grafana/provisioning
    5. chown -R 472:472 ./grafana/grafana.*
    6. chmod -R 755 ./grafana/provisioning

8) Edit prometheus configs
    
    1. Edit ./prometheus/prometheus.yml
    2. change "$KUBEMASTERIP" to your real kubernetes master IP in "federation" job targets section
    3. copy following section in "Servers" job for each VM you have, except kube nodes, replacing {vm_ip} and {vm_role} to corespondig ip and role: 
        - targets: ['{vm_ip}:9100']
          labels:
            service: "{vm_role}"

# you should get something like this
#
# scrape_configs:
#  - job_name: 'Servers'
#    scrape_interval: 15s
#    static_configs:
#      - targets: ['node-exporter:9100']
#        labels:
#          service: "monitoring"
#      - targets: ['172.17.18.140:9100']
#        labels:
#          service: "nfs"
#      - targets: ['172.17.18.141:9100']
#        labels:
#          service: "postgres-master"
#      - targets: ['172.17.18.142:9100']
#        labels:
#          service: "postgres-slave"
#      - targets: ['172.17.18.143:9100']
#        labels:
#          service: "nginx"

9) Start docker-compose to run containers

    1. docker-compose -f docker-compose.yml up -d 
    2. wait for all docker containers be up and running. Take into accout that kibana has 50s wait time before it starts to load, thish is done to asure elasticsearch is in ready state before kibana will try to connect to elasticsearch 

10) change grafana passwords

    1. login to grafana using admin user: username="admin" password="D9I9rIspos2kiDe6"
    2. change password
    3. repeat also for editor user: username="edit" password="D1fuCh86itisPApI" 
               and for readonly user: username="read" password="yEFrOtrLC0Ust5vu"
