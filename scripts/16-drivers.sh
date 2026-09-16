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

utils::print_banner "Hardware Drivers & System Remediation"

# =============================================================================
# 1. Samsung SM961/PM961 NVMe Freeze Remediation
# =============================================================================
log::step "Storage & PCIe Power Management Remediation"

is_sm961_detected=0
if lspci -nn 2>/dev/null | grep -iq "144d:a804"; then
    is_sm961_detected=1
elif lsblk -d -o MODEL 2>/dev/null | grep -iqE "MZVPW|SM961|PM961"; then
    is_sm961_detected=1
fi

if [[ "$is_sm961_detected" -eq 1 ]]; then
    log::info "Detected Samsung SM961/PM961 NVMe controller on this system."

    grub_file="/etc/default/grub"
    needs_grub_update=0
    params_to_add=()

    if [[ -f "$grub_file" ]]; then
        if ! grep -q "pcie_aspm=off" "$grub_file"; then
            params_to_add+=("pcie_aspm=off")
            needs_grub_update=1
        fi
        if ! grep -q "nvme_core.default_ps_max_latency_us=0" "$grub_file"; then
            params_to_add+=("nvme_core.default_ps_max_latency_us=0")
            needs_grub_update=1
        fi

        if [[ "$needs_grub_update" -eq 1 ]]; then
            log::warn "Applying NVMe PCIe ASPM & APST freeze fix (${params_to_add[*]}) to GRUB..."
            sudo cp "$grub_file" "${grub_file}.bak.$(date +%Y%m%d_%H%M%S)"

            sudo python3 -c '
import re, sys

grub_path = "/etc/default/grub"
params = ["pcie_aspm=off", "nvme_core.default_ps_max_latency_us=0"]

with open(grub_path, "r") as f:
    content = f.read()

pattern = r"^GRUB_CMDLINE_LINUX_DEFAULT=\"([^\"]*)\""
match = re.search(pattern, content, flags=re.MULTILINE)
if match:
    current = match.group(1).split()
    for p in params:
        if p not in current:
            current.append(p)
    new_line = f"GRUB_CMDLINE_LINUX_DEFAULT=\"{" ".join(current)}\""
    new_content = re.sub(pattern, new_line, content, flags=re.MULTILINE)
    with open(grub_path, "w") as f:
        f.write(new_content)
    print("Updated GRUB_CMDLINE_LINUX_DEFAULT successfully")
' >>"${LOG_FILE}" 2>&1

            log::info "Updating GRUB configuration (update-grub)..."
            if sudo update-grub >>"${LOG_FILE}" 2>&1; then
                log::success "NVMe freeze remediation applied to GRUB. (Reboot required for active kernel)."
            else
                log::warn "update-grub encountered an issue. Check ${LOG_FILE}."
            fi
        else
            log::success "Samsung NVMe SM961 freeze remediation is already active in GRUB config."
        fi
    fi
else
    log::info "Samsung SM961/PM961 NVMe controller not detected on this machine. No kernel patch needed."
fi

# =============================================================================
# 2. Hardware Drivers (ubuntu-drivers)
# =============================================================================
log::step "Hardware Drivers Detection & Installation"

helpers::apt_install ubuntu-drivers-common

log::info "Scanning system for recommended hardware drivers..."
detected_drivers="$(ubuntu-drivers devices 2>/dev/null || true)"
if [[ -n "$detected_drivers" ]]; then
    echo "$detected_drivers" | while IFS= read -r line; do log::info "$line"; done
fi

# NVIDIA GPU Handling
if lspci | grep -iq nvidia; then
    log::info "NVIDIA GPU detected: $(lspci | grep -i nvidia | head -n1)"

    should_install_driver="false"
    case "$INSTALL_NVIDIA_DRIVER" in
        yes) should_install_driver="true" ;;
        no)  should_install_driver="false" ;;
        ask) helpers::confirm "Install/update the recommended NVIDIA driver via ubuntu-drivers?" "y" && should_install_driver="true" ;;
    esac

    if [[ "$should_install_driver" == "true" ]]; then
        if dpkg -l | grep -q '^ii  nvidia-driver-'; then
            log::info "An NVIDIA driver package is already installed"
        else
            log::info "Installing recommended driver via ubuntu-drivers..."
            sudo ubuntu-drivers autoinstall >>"${LOG_FILE}" 2>&1 \
                && log::success "Recommended NVIDIA driver installed. A reboot is required before it takes effect." \
                || log::warn "ubuntu-drivers autoinstall reported an issue; check ${LOG_FILE}"
        fi

        if helpers::command_exists nvidia-smi; then
            log::info "nvidia-smi output:"
            nvidia-smi 2>>"${LOG_FILE}" | head -n 12 | while read -r line; do log::info "$line"; done || true
        fi
    fi

    # CUDA Toolkit
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
    fi
else
    log::info "No NVIDIA GPU detected."
    if [[ "$NON_INTERACTIVE" != "1" ]] && helpers::confirm "Run ubuntu-drivers autoinstall for any available hardware devices?" "y"; then
        sudo ubuntu-drivers autoinstall >>"${LOG_FILE}" 2>&1 || true
    fi
fi

log::success "Hardware drivers & remediation step complete"
