variables {
    image_repository = "registry.savage.zone/rabbitmq-cluster:latest"
    // automated deployments can set this to the image digest to force an update of the job
    // when the image is updated.
    image_digest = "sha256:...."
    dns_suffix = "savage.zone"
}

job "rabbitmq-cluster" {
    datacenters = ["dc1"]
    type = "service"

    group "rabbitmq" {
        // set this to the number of nodes in the cluster
        count = 3

        update {
            max_parallel      = 1
            health_check      = "checks"
            min_healthy_time  = "20s"
            healthy_deadline  = "5m"
            progress_deadline = "10m"
            stagger           = "60s"
        }

        constraint {
            attribute = "${node.class}"
            value     = "proxmox"
        }

        // We'll be using CSI volumes for persistent storage
        // this requires a number of volumes to be previously created
        // with IDs "rabbitmq-cluster-data[0]", "rabbitmq-cluster-data[1]", "rabbitmq-cluster-data[2]", etc
        volume "rabbitmq-cluster-data" {
            type            = "csi"
            read_only       = false
            source          = "rabbitmq-cluster-data"
            access_mode     = "single-node-writer"
            attachment_mode = "file-system"
            per_alloc       = true
        }

        network {
            mode = "bridge"
            port "stream" { to = 5552 }
            port "mqtt" { to = 1883 }
            port "amqp" { to = 5672 }
            
            // this is the ERL_EPMD_PORT
            port "discovery" {
                to = 4369
                static = 4369
            }

            // this is the RABBITMQ_DIST_PORT
            port "clustering" {
                to = 25672
                static = 25672
            }

            // The rabbbitmq streams plugin requires a range of ports to be open
            // for stream replication across the cluster.
            port "stream_replication" {
                to = 6000
                static = 6000
            }

            port "stream_replication_1" {
                to = 6001
                static = 6001
            }

            port "stream_replication_2" {
                to = 6002
                static = 6002
            }

            port "stream_replication_3" {
                to = 6003
                static = 6003
            }
            
            // I'm not sure these are necessary
            port "ctl0" {
                to = 35672
                static = 35672
            }

            port "ctl1" {
                to = 35673
                static = 35673
            }

            port "ctl2" {
                to = 35674
                static = 35674
            }

            port "ctl4" {
                to = 35675
                static = 35675
            }
            
            // ensure that the DNS server is set to dnsmasq
            dns {
                servers = ["127.0.0.1"]
            }
        }

        // Consul service registration for the management UI and API
        service {
            name = "rabbitmq-cluster-management"
            tags = [
                "rabbitmq",
                "traefik.enable=true",
                "traefik.consulcatalog.connect=true",
                "traefik.http.routers.rabbitmq-cluster-management.entrypoints=https",
                "traefik.http.routers.rabbitmq-cluster-management.middlewares=rabbitmq-cluster-management-compress,rabbitmq-cluster-management-retry",
                "traefik.http.middlewares.rabbitmq-cluster-management-compress.compress=true",
                "traefik.http.middlewares.rabbitmq-cluster-management-retry.retry.attempts=5",
                "traefik.http.middlewares.rabbitmq-cluster-management-retry.retry.initialinterval=100ms",
            ]
            port = 15672

            connect {
                sidecar_service {}
                
                // Per this issue:  https://github.com/hashicorp/nomad/issues/11056
                // The extra_hosts field doesn't work when set in the task's config block, and should be
                // set in the sidecar_task block instead.  In our case we have several sidecar tasks,
                // so we need to set it in each one.
                sidecar_task {
                    config {
                        extra_hosts = [
                            "rabbitmq-cluster-${NOMAD_ALLOC_INDEX}.service.consul:127.0.0.1"
                        ]
                    }
                }
            }

            check {
                expose   = true
                type     = "http"
                // /api/index.html is the only path that doesn't require authentication,
                // so it's a reasonable health check endpoint
                path     = "/api/index.html"
                interval = "30s"
                timeout  = "2s"
            }

            check_restart {
                limit           = 3
                grace           = "120s"
                ignore_warnings = false
            }
        }

        service {
            name = "rabbitmq-cluster-prometheus"
            tags = [
                "rabbitmq",
                "traefik.enable=true",
                "traefik.consulcatalog.connect=true",
                "traefik.http.routers.rabbitmq-cluster-prometheus.entrypoints=https",
                "traefik.http.routers.rabbitmq-cluster-prometheus.middlewares=rabbitmq-cluster-prometheus-compress",
                "traefik.http.middlewares.rabbitmq-cluster-prometheus-compress.compress=true",
            ]
            port = 15692

            connect {
                sidecar_service {}
                
                // See above
                sidecar_task {
                    config {
                        extra_hosts = [
                            "rabbitmq-cluster-${NOMAD_ALLOC_INDEX}.service.consul:127.0.0.1"
                        ]
                    }
                }
            }
        }

        service {
            name = "rabbitmq-cluster-amqp"
            tags = [
                "rabbitmq",
                "traefik.enable=true",
                "traefik.tcp.routers.rabbitmq-cluster-amqp-ingress.entrypoints=https",
                "traefik.tcp.routers.rabbitmq-cluster-amqp-ingress.rule=HostSNI(`rabbitmq-cluster-amqp.${var.dns_suffix}`)",
                "traefik.tcp.routers.rabbitmq-cluster-amqp-ingress.tls=true",
            ]
            port = "amqp"
        }
        
        service {
            name = "rabbitmq-cluster-stream"
            tags = [
                "rabbitmq",
                "traefik.enable=true",
                "traefik.tcp.routers.rabbitmq-cluster-stream-ingress.entrypoints=https",
                "traefik.tcp.routers.rabbitmq-cluster-stream-ingress.rule=HostSNI(`rabbitmq-cluster-stream.${var.dns_suffix}`)",
                "traefik.tcp.routers.rabbitmq-cluster-stream-ingress.tls=true",
            ]
            port = "stream"
        }

        service {
            name = "rabbitmq-cluster-mqtt"
            tags = [
                "rabbitmq",
                "traefik.enable=true",
                "traefik.tcp.routers.rabbitmq-cluster-mqtt-ingress.entrypoints=https",
                "traefik.tcp.routers.rabbitmq-cluster-mqtt-ingress.rule=HostSNI(`rabbitmq-cluster-mqtt.${var.dns_suffix}`)",
                "traefik.tcp.routers.rabbitmq-cluster-mqtt-ingress.tls=true",
            ]
            port = "mqtt"
        }

        service {
            name = "rabbitmq-mqtt-web"
            tags = [
                "rabbitmq",
                "traefik.enable=true",
                "traefik.consulcatalog.connect=true",
                "traefik.http.routers.rabbitmq-cluster-mqtt-web.entrypoints=https",
                "traefik.http.routers.rabbitmq-cluster-mqtt-web.middlewares=rabbitmq-cluster-mqtt-web-compress",
                "traefik.http.middlewares.rabbitmq-cluster-mqtt-web-compress.compress=true",
            ]
            port = 15675

            connect {
                sidecar_service {}
                
                // See above
                sidecar_task {
                    config {
                        extra_hosts = [
                            "rabbitmq-cluster-${NOMAD_ALLOC_INDEX}.service.consul:127.0.0.1"
                        ]
                    }
                }
            }
        }

        service {
            name = "rabbitmq-cluster-${NOMAD_ALLOC_INDEX}"
            tags = [
                "rabbitmq",
            ]
            port = "discovery"
        }

        task "rabbitmq" {
            driver = "docker"

            volume_mount {
                volume      = "rabbitmq-cluster-data"
                destination = "/var/lib/rabbitmq"
                read_only   = false
            }

            env {
                RABBITMQ_USE_LONGNAME = "true"
                RABBITMQ_NODENAME = "rabbitmq@rabbitmq-cluster-${NOMAD_ALLOC_INDEX}.service.consul"
                
                // You probably want to get these from vault or otherwise store them securely
                RABBITMQ_DEFAULT_USER = "guest"
                RABBITMQ_DEFAULT_PASS = "guest"
                RABBITMQ_ERLANG_COOKIE = "somethingsecret"
                
                // This will be used in the config template below to limit
                // the memory available to the rabbitmq process, otherwise it will think
                // it has access to all the memory on the host
                RABBITMQ_TOTAL_MEMORY_AVAILABLE_OVERRIDE_VALUE = "1GB"
                
                RABBITMQ_CLUSTER_NAME = "rabbitmq-cluster@${var.dns_suffix}"
                
                // ports
                ERL_EPMD_PORT = "4369"
                RABBITMQ_NODE_PORT = "5672"
                RABBITMQ_DIST_PORT = "25672"
                RABBITMQ_CTL_DIST_PORT_MIN = "35672"
                RABBITMQ_CTL_DIST_PORT_MAX = "35675"
            }

            config {
                image = var.image_repository
                volumes = [
                    "local/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf",
                    "local/enabled_plugins:/etc/rabbitmq/enabled_plugins",
                    "local/advanced.config:/etc/rabbitmq/advanced.config",
                ]
                ports = [
                    // clustering
                    "discovery", "clustering", 
                    // cli tools
                    "ctl0", "ctl1", "ctl2", "ctl3",
                    // stream replication
                    "stream_replication", "stream_replication_1", "stream_replication_2", "stream_replication_3",
                    // protocols
                    "stream", "mqtt", "amqp"
                ]
                
                // this doesn't work per https://github.com/hashicorp/nomad/issues/11056, see above
                extra_hosts = [
                    "rabbitmq-cluster-${NOMAD_ALLOC_INDEX}.service.consul:127.0.0.1"
                ]
            }

            meta {
                image_digest = "${var.image_digest}"
            }

            // limit the stream replication ports to this range
            template {
                data        = <<EOH
[{osiris, [{port_range, {6000, 6003}}]}].
EOH
                destination = "local/advanced.config"
            }

            template {
                data        = <<EOH
[rabbitmq_shovel_management,rabbitmq_shovel,rabbitmq_management,rabbitmq_prometheus,rabbitmq_mqtt,rabbitmq_stomp,rabbitmq_stream,rabbitmq_web_mqtt,rabbitmq_web_mqtt_examples].
EOH
                destination = "local/enabled_plugins"
            }

            template {
                data        = <<EOH
# Authentication Settings
auth_backends.1 = internal

# Clustering setup:  set the number of nodes to equal the number of nodes in the cluster
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbitmq@rabbitmq-cluster-0.service.consul
cluster_formation.classic_config.nodes.2 = rabbitmq@rabbitmq-cluster-1.service.consul
cluster_formation.classic_config.nodes.3 = rabbitmq@rabbitmq-cluster-2.service.consul

# Logging Settings
log.console = true
log.console.level = info
log.default.level = info

# General settings
total_memory_available_override_value = $(RABBITMQ_TOTAL_MEMORY_AVAILABLE_OVERRIDE_VALUE)
cluster_name = $(RABBITMQ_CLUSTER_NAME)
EOH
                destination = "local/rabbitmq.conf"
            }

            resources {
                cpu = 100
                memory = 512
                memory_max = 1024
            }
        }
    }
}