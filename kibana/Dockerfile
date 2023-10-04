ARG ELASTIC_VERSION

# https://www.docker.elastic.co/
FROM docker.elastic.co/kibana/kibana:${ELASTIC_VERSION}

# Add your kibana plugins setup here
# Example: RUN kibana-plugin install <name|url>

# Install the jq package using apt
USER root
RUN apt-get update && apt-get install -y jq && apt-get clean
COPY ./start-kibana.sh /usr/share/kibana/start-kibana.sh
RUN chmod +x /usr/share/kibana/start-kibana.sh && chown kibana:kibana /usr/share/kibana/start-kibana.sh

# Start Kibana
USER kibana
CMD ["/usr/share/kibana/bin/kibana"]