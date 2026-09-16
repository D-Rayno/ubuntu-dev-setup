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

# -----------------------------------------------------------------------------
# install_local_or_remote_deb <pkg_name> <local_glob> <remote_url>
# Installs a deb package, prioritizing any already-downloaded deb in ~/Downloads.
# -----------------------------------------------------------------------------
install_local_or_remote_deb() {
    local pkg_name="$1"
    local local_glob="$2"
    local remote_url="$3"

    if helpers::is_installed "$pkg_name"; then
        log::info "${pkg_name} already installed"
        return 0
    fi

    local user_downloads="$(helpers::current_user_home)/Downloads"
    local local_candidate=""
    for f in ${user_downloads}/${local_glob}; do
        if [[ -f "$f" ]]; then
            local_candidate="$f"
            break
        fi
    done

    if [[ -n "$local_candidate" ]]; then
        log::info "Found local .deb for ${pkg_name}: $(basename "$local_candidate")"
        helpers::wait_for_apt_lock
        if helpers::with_apt_lock sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 install -y "$local_candidate" >>"${LOG_FILE}" 2>&1; then
            log::success "Installed ${pkg_name} from local .deb"
            return 0
        fi
    fi

    log::info "Downloading and installing official .deb for ${pkg_name}..."
    downloads::install_deb "$remote_url" "$pkg_name"
}

# ----------------------------- Google Chrome --------------------------------
log::step "Google Chrome (deb)"
install_local_or_remote_deb "google-chrome-stable" "google-chrome*.deb" "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"

# --------------------------- Visual Studio Code -----------------------------
log::step "Visual Studio Code (deb)"
install_local_or_remote_deb "code" "code*.deb" "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"

# --------------------------------- Discord ----------------------------------
log::step "Discord (deb)"
install_local_or_remote_deb "discord" "discord*.deb" "https://discord.com/api/download?platform=linux&format=deb"

# --------------------------------- Postman ----------------------------------
log::step "Postman"
if helpers::command_exists postman || [[ -d /opt/Postman ]] || snap list postman >/dev/null 2>&1; then
    log::info "Postman already installed"
else
    log::info "Installing Postman standalone..."
    tmp_postman_tar="${DEVBOOTSTRAP_TMP_DIR}/postman.tar.gz"
    if downloads::fetch "https://dl.pstmn.io/download/latest/linux_64" "$tmp_postman_tar"; then
        sudo mkdir -p /opt
        sudo tar -xzf "$tmp_postman_tar" -C /opt >>"${LOG_FILE}" 2>&1
        sudo ln -sf /opt/Postman/app/postman /usr/local/bin/postman
        rm -f "$tmp_postman_tar"

        # Create desktop launcher
        user_home="$(helpers::current_user_home)"
        mkdir -p "${user_home}/.local/share/applications"
        cat <<'EOF' > "${user_home}/.local/share/applications/postman.desktop"
[Desktop Entry]
Name=Postman
GenericName=API Client
Comment=REST & GraphQL API Development Environment
Exec=/opt/Postman/app/postman %U
Icon=/opt/Postman/app/resources/app/assets/icon.png
Terminal=false
Type=Application
Categories=Development;
EOF
        log::success "Postman installed to /opt/Postman"
    elif helpers::command_exists snap; then
        log::info "Falling back to snap install for Postman..."
        sudo snap install postman >>"${LOG_FILE}" 2>&1 && log::success "Postman installed via snap" || log::warn "Postman install failed"
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
log::step "Additional Snap Applications"
if helpers::command_exists snap; then
    for entry in "${SNAP_APPS[@]}"; do
        candidates_part="${entry%%:*}"
        snap_flag="${entry#*:}"
        IFS='|' read -ra candidates <<< "$candidates_part"

        # Skip postman if already handled above
        [[ "$candidates_part" == *"postman"* ]] && continue

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

        for candidate in "${candidates[@]}"; do
            log::info "Installing snap: ${candidate} ${snap_flag:+(--$snap_flag)}"
            if [[ -n "$snap_flag" ]]; then
                if sudo snap install "$candidate" "--${snap_flag}" >>"${LOG_FILE}" 2>&1; then
                    log::success "Installed snap ${candidate}"
                    break
                fi
            else
                if sudo snap install "$candidate" >>"${LOG_FILE}" 2>&1; then
                    log::success "Installed snap ${candidate}"
                    break
                fi
            fi
        done
    done
fi

log::success "Desktop applications step complete"
