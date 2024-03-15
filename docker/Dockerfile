FROM rabbitmq:3-management

ENV DEBIAN_FRONTEND=noninteractive
# Install dnsmasq, gettext (for envsubst) and other tools
# Only dnsmasq and gettext are required, the
# other tools are for debugging
RUN apt update && apt install -y \
    dnsmasq gettext dnsutils lsof iputils-ping \
    curl nano jq net-tools nmap && \
    rm -rf /var/lib/apt/lists/*
# Override the default entrypoint    
COPY --chmod=755 entrypoint.sh /usr/local/bin/new-docker-entrypoint.sh 
# Copy the dnsmasq configuration template
COPY --chmod=666 10-consul-dns-template /etc/dnsmasq.d/10-consul-dns-template

# set defaults for variables used in the dnsmasq configuration
ENV CONSUL_DNS_HOST_IP=10.4.1.220
ENV CONSUL_DNS_HOST_PORT=8600
ENV DNS_SERVER=1.1.1.1

ENTRYPOINT [ "new-docker-entrypoint.sh" ]
CMD ["rabbitmq-server"]
