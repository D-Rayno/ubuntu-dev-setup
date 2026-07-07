#!/usr/bin/env bash
# =============================================================================
# scripts/09-docker.sh
# -----------------------------------------------------------------------------
# Installs Docker Engine, the Compose plugin, and Buildx from Docker's
# official apt repository, per docs.docker.com/engine/install/ubuntu.
# Enables the service, adds the invoking user to the `docker` group, and
# writes a sane default daemon.json if one doesn't already exist.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="09-docker"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Docker"

if helpers::is_installed docker-ce; then
    log::info "Docker Engine already installed: $(docker --version 2>/dev/null || echo unknown)"
else
    log::info "Removing any conflicting legacy Docker packages..."
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        sudo apt-get remove -y "$pkg" >>"${LOG_FILE}" 2>&1 || true
    done

    helpers::apt_install ca-certificates curl

    ARCH="$(dpkg --print-architecture)"
    CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"

    helpers::add_apt_repo \
        "docker" \
        "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
        "https://download.docker.com/linux/ubuntu/gpg" \
        "/etc/apt/keyrings/docker.gpg"

    helpers::apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin "${DOCKER_COMPOSE_PLUGIN}"
    log::success "Docker Engine, Buildx, and Compose plugin installed"
fi

log::info "Enabling and starting Docker service..."
sudo systemctl enable docker >>"${LOG_FILE}" 2>&1
sudo systemctl start docker >>"${LOG_FILE}" 2>&1
log::success "Docker service enabled and started"

current_user="$(id -un)"
if id -nG "$current_user" | grep -qw docker; then
    log::info "User '${current_user}' already in docker group"
else
    sudo usermod -aG docker "$current_user"
    log::success "Added '${current_user}' to docker group (log out/in, or run 'newgrp docker', to take effect)"
fi

DAEMON_JSON="/etc/docker/daemon.json"
if [[ -f "$DAEMON_JSON" ]]; then
    log::info "daemon.json already exists, leaving it untouched"
else
    log::info "Writing default daemon.json..."
    sudo mkdir -p /etc/docker
    sudo tee "$DAEMON_JSON" >/dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    sudo systemctl restart docker >>"${LOG_FILE}" 2>&1
    log::success "Default daemon.json written and Docker restarted"
fi

log::info "Verifying Docker installation..."
if sudo docker run --rm hello-world >>"${LOG_FILE}" 2>&1; then
    log::success "Docker verified: hello-world container ran successfully"
else
    log::warn "Docker hello-world test failed. Check ${LOG_FILE}."
fi

docker --version 2>/dev/null | while read -r line; do log::info "$line"; done
docker compose version 2>/dev/null | while read -r line; do log::info "$line"; done
docker buildx version 2>/dev/null | while read -r line; do log::info "$line"; done

log::success "Docker step complete"
