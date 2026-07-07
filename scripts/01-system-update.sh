#!/usr/bin/env bash
# =============================================================================
# scripts/01-system-update.sh
# -----------------------------------------------------------------------------
# Updates the apt package index and upgrades existing packages. This runs
# first so every later module works from an up-to-date package cache.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="01-system-update"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "System Update"

log::info "Checking Ubuntu release..."
if helpers::command_exists lsb_release; then
    log::info "Detected: $(lsb_release -ds)"
else
    log::warn "lsb_release not found yet; will be installed in base packages step."
fi

log::info "Refreshing apt package index..."
sudo apt-get update -y >>"${LOG_FILE}" 2>&1
log::success "apt package index refreshed"
touch "/tmp/.devbootstrap_apt_updated_$(date +%Y%m%d)"

log::info "Upgrading existing packages (this may take a while on a fresh install)..."
if DEBIAN_FRONTEND=noninteractive sudo -E apt-get upgrade -y >>"${LOG_FILE}" 2>&1; then
    log::success "System packages upgraded"
else
    log::warn "apt-get upgrade reported issues; check ${LOG_FILE}. Continuing."
fi

log::info "Removing unused packages..."
sudo apt-get autoremove -y >>"${LOG_FILE}" 2>&1 || log::warn "autoremove reported issues"

log::success "System update step complete"
