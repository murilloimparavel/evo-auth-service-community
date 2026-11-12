# =============================================================================
# EVO-AUTH-SERVICE - Development Dockerfile
# =============================================================================

# Pin the Ruby patch release, Debian suite, and upstream multi-platform manifest.
FROM ruby:3.4.12-slim-trixie@sha256:65680693964528b522a38d85ec5065538c7ab9e75268802aab9770f39ee56de0

# Set working directory
WORKDIR /rails

# Install system dependencies
RUN apt-get update -qq && \
    apt-get upgrade --no-install-recommends -y && \
    apt-get install --no-install-recommends -y \
    build-essential \
    curl \
    git \
    libpq-dev \
    libyaml-dev \
    pkg-config \
    postgresql-client \
    libjemalloc2 \
    libvips \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# RAILS_ENV is configurable at build time: defaults to 'development' (keeps the
# local compose working); pass --build-arg RAILS_ENV=production for deploy images.
ARG RAILS_ENV=development
ENV RAILS_ENV=${RAILS_ENV} \
    BUNDLE_PATH="/usr/local/bundle"

# Copy Gemfile and install dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy application code (excluding problematic files)
COPY --chown=1000:1000 . .

# Remove production-specific files that might cause issues
RUN rm -f bin/thrust bin/docker-entrypoint

# Install role-aware healthcheck before switching to the non-root user.
COPY --chown=1000:1000 bin/healthcheck /usr/local/bin/evo-auth-healthcheck
RUN chmod +x /usr/local/bin/evo-auth-healthcheck

# EVO-1999: entrypoint that runs migrations on image boot, so any orchestrator
# (incl. CapRover, which ignores the compose command) brings up an up-to-date
# schema. Installed before USER so we can set permissions as root.
COPY --chown=1000:1000 docker-entrypoint.sh /usr/local/bin/evo-auth-entrypoint
RUN chmod +x /usr/local/bin/evo-auth-entrypoint

# Normalize CRLF->LF on all scripts: a Windows checkout leaves \r in shebangs
# (#!/bin/sh\r), making the kernel look for "/bin/sh\r" -> "not found" (exit
# 127). On the HEALTHCHECK this marks the container unhealthy and the gateway
# answers 502; on bin/* it breaks e.g. `bin/rails runner` the same way; on the
# entrypoint it aborts the boot.
RUN sed -i 's/\r$//' /usr/local/bin/evo-auth-healthcheck /usr/local/bin/evo-auth-entrypoint bin/* \
    && chmod +x bin/*

# Create non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails /rails

# Switch to non-root user
USER rails:rails

# Expose port
EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["/usr/local/bin/evo-auth-healthcheck"]

# EVO-1999: the image migrates on boot (RUN_MIGRATIONS gate, default true) and
# starts the server. Orchestrators that pass their own command (e.g. sidekiq)
# still go through the entrypoint — set RUN_MIGRATIONS=false on those to skip it.
ENTRYPOINT ["/usr/local/bin/evo-auth-entrypoint"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3001"]
