#!/usr/bin/env bash
# =============================================================================
# scripts/15-desktop-apps.sh
# -----------------------------------------------------------------------------
# Installs desktop GUI applications.
#
# Policy (per project spec):
#   - Snap is used ONLY for: Android Studio, Postman, Telegram, WhatsApp
#   - Everything else uses each vendor's official apt repository or an
#     official .deb, never an unofficial PPA.
#
# Apps installed via official repo/.deb:
#   Google Chrome, Visual Studio Code, Discord, Antigravity IDE, TablePlus
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="15-desktop-apps"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Desktop Applications"

helpers::apt_install software-properties-common apt-transport-https ca-certificates gnupg

ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"

# ----------------------------- Google Chrome --------------------------------
log::step "Google Chrome"
if helpers::is_installed google-chrome-stable; then
    log::info "Google Chrome already installed"
else
    helpers::add_apt_repo \
        "google-chrome" \
        "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        "https://dl.google.com/linux/linux_signing_key.pub" \
        "/etc/apt/keyrings/google-chrome.gpg"
    helpers::apt_install google-chrome-stable
fi

# --------------------------- Visual Studio Code -----------------------------
log::step "Visual Studio Code"
if helpers::is_installed code; then
    log::info "VS Code already installed"
else
    helpers::add_apt_repo \
        "vscode" \
        "deb [arch=${ARCH},arm64,armhf signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
        "https://packages.microsoft.com/keys/microsoft.asc" \
        "/etc/apt/keyrings/microsoft.gpg"
    helpers::apt_install code
fi

# --------------------------------- Discord ----------------------------------
log::step "Discord"
if helpers::is_installed discord; then
    log::info "Discord already installed"
else
    downloads::install_deb "https://discord.com/api/download?platform=linux&format=deb" discord
fi

# ------------------------------ Antigravity IDE -----------------------------
log::step "Antigravity IDE"
if helpers::is_installed antigravity || helpers::command_exists antigravity-ide; then
    log::info "Antigravity IDE already installed"
else
    log::info "Adding Google's official Antigravity apt repository..."
    if helpers::add_apt_repo \
        "antigravity" \
        "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" \
        "https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg" \
        "/etc/apt/keyrings/antigravity-repo-key.gpg"; then
        if helpers::apt_install antigravity; then
            log::success "Antigravity IDE installed via official apt repository"
        else
            log::warn "Antigravity apt package unavailable/out of date. Google currently ships newer Antigravity builds as a Linux tarball."
            log::warn "Download the latest tarball manually from https://antigravity.google/download/linux and follow Google's Linux install instructions."
        fi
    else
        log::warn "Could not configure Antigravity apt repository. See ${LOG_FILE}."
    fi
fi

# -------------------------------- TablePlus ---------------------------------
log::step "TablePlus"
if helpers::is_installed tableplus; then
    log::info "TablePlus already installed"
else
    TABLEPLUS_REPO_PATH="debian/24"
    [[ "$ARCH" == "arm64" ]] && TABLEPLUS_REPO_PATH="debian/24-arm"
    if helpers::add_apt_repo \
        "tableplus" \
        "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/tableplus.gpg] https://deb.tableplus.com/${TABLEPLUS_REPO_PATH} tableplus main" \
        "https://deb.tableplus.com/apt.tableplus.com.gpg.key" \
        "/etc/apt/keyrings/tableplus.gpg"; then
        helpers::apt_install tableplus || log::warn "TablePlus install failed; check ${LOG_FILE}"
    fi
fi

# ------------------------------- Snap apps ----------------------------------
log::step "Snap Applications (Android Studio, Postman, Telegram, WhatsApp)"
utils::require_cmd snap "Ensure scripts/02-base-packages.sh ran successfully (installs snapd)."

for entry in "${SNAP_APPS[@]}"; do
    candidates_part="${entry%%:*}"
    snap_flag="${entry#*:}"
    IFS='|' read -ra candidates <<< "$candidates_part"

    already_installed=""
    for candidate in "${candidates[@]}"; do
        if snap list "$candidate" >/dev/null 2>&1; then
            already_installed="$candidate"
            break
        fi
    done

    if [[ -n "$already_installed" ]]; then
        log::info "Snap '${already_installed}' already installed"
        continue
    fi

    installed_ok=0
    for candidate in "${candidates[@]}"; do
        log::info "Installing snap: ${candidate} ${snap_flag:+(--$snap_flag)}"
        if [[ -n "$snap_flag" ]]; then
            if sudo snap install "$candidate" "--${snap_flag}" >>"${LOG_FILE}" 2>&1; then
                log::success "Installed snap ${candidate}"
                installed_ok=1
                break
            fi
        else
            if sudo snap install "$candidate" >>"${LOG_FILE}" 2>&1; then
                log::success "Installed snap ${candidate}"
                installed_ok=1
                break
            fi
        fi
        log::warn "Snap '${candidate}' failed or is unavailable; trying next candidate if any."
    done

    if [[ "$installed_ok" -eq 0 ]]; then
        log::warn "None of the candidates for '${candidates_part}' could be installed (see ${LOG_FILE})."
    fi
done

log::success "Desktop applications step complete"
