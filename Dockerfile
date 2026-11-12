# =============================================================================
# EVO-AUTH-SERVICE - Development Dockerfile
# =============================================================================

# Use the patched Ruby 3.4 line on a supported Alpine release.
ARG RUBY_VERSION=3.4.12
ARG RAILS_ENV=development
FROM ruby:${RUBY_VERSION}-alpine3.24 AS base

# Keep the runtime base current with Alpine security updates.
RUN apk update && \
    apk upgrade --no-cache && \
    apk add --no-cache \
    bash \
    libpq \
    tzdata \
    yaml

FROM base AS build

# Set working directory
WORKDIR /rails
ARG RAILS_ENV

# Install build dependencies and the tools needed by the local development image.
RUN apk add --no-cache \
    build-base \
    git \
    postgresql-dev \
    yaml-dev

# RAILS_ENV is configurable at build time: defaults to 'development' (keeps the
# local compose working); pass --build-arg RAILS_ENV=production for deploy images.
ENV RAILS_ENV=${RAILS_ENV} \
    BUNDLE_PATH="/usr/local/bundle"

# Copy Gemfile and install dependencies. Production images omit development and
# test-only gems, reducing runtime surface while preserving local Docker Compose.
COPY Gemfile Gemfile.lock ./
RUN if [ "$RAILS_ENV" = "production" ]; then \
      bundle config set --local without 'development test'; \
    fi && bundle install

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

FROM base AS runtime
WORKDIR /rails

ARG RAILS_ENV
ENV RAILS_ENV=${RAILS_ENV} \
    BUNDLE_PATH="/usr/local/bundle"

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails
COPY --from=build /usr/local/bin/evo-auth-healthcheck /usr/local/bin/evo-auth-healthcheck
COPY --from=build /usr/local/bin/evo-auth-entrypoint /usr/local/bin/evo-auth-entrypoint

# Create non-root user for security
RUN addgroup -S -g 1000 rails && \
    adduser -S -u 1000 -G rails -h /home/rails -s /bin/ash rails && \
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
