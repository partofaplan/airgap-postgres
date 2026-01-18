# HAProxy for PostgreSQL Load Balancing
# Configured for air-gapped environments

FROM haproxy:2.9

# Create haproxy user directory
USER root
RUN mkdir -p /run/haproxy && chown haproxy:haproxy /run/haproxy

# Copy default configuration (will be overridden by ConfigMap in K8s)
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg

# Switch back to haproxy user
USER haproxy

# Expose ports
EXPOSE 5432 5433 8404

# Health check
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://localhost:8404/stats || exit 1
