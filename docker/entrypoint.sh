#!/usr/bin/env bash

# replace the variables in the dnsmasq config file template
envsubst < /etc/dnsmasq.d/10-consul-dns-template > /etc/dnsmasq.d/10-consul-dns
rm /etc/dnsmasq.d/10-consul-dns-template

# start dnsmasq, then start the docker entrypoint
/etc/init.d/dnsmasq start
/usr/local/bin/docker-entrypoint.sh $1



