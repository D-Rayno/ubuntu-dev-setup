#!/usr/bin/env bash
# =============================================================================
# scripts/12-redis.sh
# -----------------------------------------------------------------------------
# Installs Redis from the official Ubuntu repository, enables the service,
# applies a couple of safe local-development tweaks, and verifies with
# redis-cli ping.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="12-redis"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Redis"

helpers::apt_install redis-server

REDIS_CONF="/etc/redis/redis.conf"
if [[ -f "$REDIS_CONF" ]]; then
    log::info "Applying local-development tuning to ${REDIS_CONF}..."
    # supervised systemd: lets systemd manage the process correctly.
    sudo sed -i 's/^supervised .*/supervised systemd/' "$REDIS_CONF"
    # Bind to loopback only for local dev safety (already default, but explicit).
    if ! grep -qE '^bind 127\.0\.0\.1' "$REDIS_CONF"; then
        sudo sed -i 's/^bind .*/bind 127.0.0.1 -::1/' "$REDIS_CONF" || true
    fi
    log::success "redis.conf tuned for local development"
fi

sudo systemctl enable redis-server >>"${LOG_FILE}" 2>&1
sudo systemctl restart redis-server >>"${LOG_FILE}" 2>&1
log::success "Redis service enabled and started"

log::info "Verifying Redis with redis-cli ping..."
if [[ "$(redis-cli ping 2>>"${LOG_FILE}")" == "PONG" ]]; then
    log::success "Redis responded PONG"
else
    log::warn "Redis did not respond as expected. Check ${LOG_FILE}."
fi

log::success "Redis step complete"
