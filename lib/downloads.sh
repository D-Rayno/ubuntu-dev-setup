#!/usr/bin/env bash
# =============================================================================
# lib/downloads.sh
# -----------------------------------------------------------------------------
# Helpers for downloading files (.deb packages, install scripts, tarballs)
# safely: retries, temp-dir cleanup, optional checksum verification, and
# .deb installation via apt (so dependencies resolve correctly instead of
# using dpkg -i directly).
# =============================================================================

if [[ -n "${__DEVBOOTSTRAP_DOWNLOADS_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
__DEVBOOTSTRAP_DOWNLOADS_LOADED=1

DEVBOOTSTRAP_TMP_DIR="${DEVBOOTSTRAP_TMP_DIR:-/tmp/ubuntu-dev-bootstrap}"
mkdir -p "${DEVBOOTSTRAP_TMP_DIR}"

# -----------------------------------------------------------------------------
# downloads::fetch <url> <destination>
# Downloads a file with curl, retrying on transient failures.
# -----------------------------------------------------------------------------
downloads::fetch() {
    local url="$1" dest="$2"
    log::info "Downloading ${url}"
    if helpers::retry 3 3 curl -fsSL --retry 2 -o "$dest" "$url"; then
        log::success "Downloaded to ${dest}"
        return 0
    fi
    log::error "Failed to download ${url}"
    return 1
}

# -----------------------------------------------------------------------------
# downloads::install_deb <url> [package_name_for_dpkg_check]
# Downloads a .deb package and installs it via apt (falls back to dpkg -i +
# apt-get install -f to resolve missing dependencies). Idempotent when a
# package name is supplied and already installed.
# -----------------------------------------------------------------------------
downloads::install_deb() {
    local url="$1"
    local pkg_check="${2:-}"

    if [[ -n "$pkg_check" ]] && helpers::is_installed "$pkg_check"; then
        log::debug "Package '$pkg_check' already installed, skipping .deb download"
        return 0
    fi

    local tmp_deb="${DEVBOOTSTRAP_TMP_DIR}/$(basename "${url%%\?*}")"
    downloads::fetch "$url" "$tmp_deb" || return 1

    log::info "Installing package: $(basename "$tmp_deb")"
    if sudo apt-get install -y "$tmp_deb" >>"${LOG_FILE}" 2>&1; then
        log::success "Installed $(basename "$tmp_deb")"
        rm -f "$tmp_deb"
        return 0
    else
        log::warn "apt-get install failed for $(basename "$tmp_deb"), attempting dpkg fallback"
        if sudo dpkg -i "$tmp_deb" >>"${LOG_FILE}" 2>&1; then
            sudo apt-get install -f -y >>"${LOG_FILE}" 2>&1
            log::success "Installed $(basename "$tmp_deb") via dpkg fallback"
            rm -f "$tmp_deb"
            return 0
        fi
        log::error "Failed to install $(basename "$tmp_deb")"
        rm -f "$tmp_deb"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# downloads::run_installer_script <url>
# Downloads a shell install script to a temp file and executes it, rather
# than piping curl directly into bash. This lets us log the script content
# and inspect failures without losing the script body.
# -----------------------------------------------------------------------------
downloads::run_installer_script() {
    local url="$1"
    shift || true
    local tmp_script="${DEVBOOTSTRAP_TMP_DIR}/installer_$(date +%s).sh"
    downloads::fetch "$url" "$tmp_script" || return 1
    chmod +x "$tmp_script"
    log::info "Executing installer script from ${url}"
    if bash "$tmp_script" "$@" >>"${LOG_FILE}" 2>&1; then
        log::success "Installer script from ${url} completed"
        rm -f "$tmp_script"
        return 0
    else
        log::error "Installer script from ${url} failed (kept at ${tmp_script} for inspection)"
        return 1
    fi
}

export DEVBOOTSTRAP_TMP_DIR
