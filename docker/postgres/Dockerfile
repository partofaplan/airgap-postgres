# PostgreSQL 18 for Air-gapped Environments
# This image includes additional tools needed for HA and backup operations

FROM postgres:18

# Install additional tools for health checks and backup
RUN apt-get update && apt-get install -y --no-install-recommends \
    netcat-openbsd \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Add custom entrypoint scripts support
COPY docker-entrypoint-initdb.d/ /docker-entrypoint-initdb.d/

# Expose PostgreSQL port
EXPOSE 5432

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD pg_isready -U postgres || exit 1
