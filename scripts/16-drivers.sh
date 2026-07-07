#!/usr/bin/env bash
# =============================================================================
# scripts/16-drivers.sh
# -----------------------------------------------------------------------------
# Installs the recommended NVIDIA driver via Ubuntu's `ubuntu-drivers`
# autodetection tool (official Ubuntu tooling, no manual PPA), and optionally
# the CUDA toolkit from NVIDIA's official apt repository.
#
# Controlled via config/versions.conf:
#   INSTALL_NVIDIA_DRIVER = ask | yes | no
#   INSTALL_CUDA_TOOLKIT  = ask | yes | no
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="16-drivers"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "NVIDIA Drivers"

if ! lspci | grep -iq nvidia; then
    log::info "No NVIDIA GPU detected via lspci. Skipping driver installation."
    exit 0
fi

log::info "NVIDIA GPU detected: $(lspci | grep -i nvidia | head -n1)"

should_install_driver="false"
case "$INSTALL_NVIDIA_DRIVER" in
    yes) should_install_driver="true" ;;
    no)  should_install_driver="false" ;;
    ask) helpers::confirm "Install the recommended NVIDIA driver?" "y" && should_install_driver="true" ;;
esac

if [[ "$should_install_driver" == "true" ]]; then
    if helpers::is_installed nvidia-driver-535 || dpkg -l | grep -q '^ii  nvidia-driver-'; then
        log::info "An NVIDIA driver package already appears to be installed"
    else
        helpers::apt_install ubuntu-drivers-common
        log::info "Detecting and installing recommended driver via ubuntu-drivers..."
        sudo ubuntu-drivers autoinstall >>"${LOG_FILE}" 2>&1 \
            && log::success "Recommended NVIDIA driver installed. A reboot is required before it takes effect." \
            || log::warn "ubuntu-drivers autoinstall reported an issue; check ${LOG_FILE}"
    fi

    if helpers::command_exists nvidia-smi; then
        log::info "nvidia-smi output (may require reboot to reflect a freshly installed driver):"
        nvidia-smi 2>>"${LOG_FILE}" | while read -r line; do log::info "$line"; done || true
    fi
else
    log::info "Skipping NVIDIA driver installation"
fi

should_install_cuda="false"
case "$INSTALL_CUDA_TOOLKIT" in
    yes) should_install_cuda="true" ;;
    no)  should_install_cuda="false" ;;
    ask) helpers::confirm "Install the CUDA toolkit as well? (optional, large download)" "n" && should_install_cuda="true" ;;
esac

if [[ "$should_install_cuda" == "true" ]]; then
    log::step "CUDA Toolkit"
    CODENAME_NO_DOT="$(. /etc/os-release && echo "${VERSION_ID//./}")"
    cuda_keyring_deb="cuda-keyring_1.1-1_all.deb"
    if ! helpers::is_installed cuda-keyring; then
        downloads::install_deb "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${CODENAME_NO_DOT}/x86_64/${cuda_keyring_deb}" cuda-keyring
    fi
    helpers::apt_update_once
    helpers::apt_install cuda-toolkit
    log::success "CUDA toolkit installed. Verify later with: nvcc --version"
else
    log::info "Skipping CUDA toolkit installation"
fi

log::success "NVIDIA drivers step complete"
