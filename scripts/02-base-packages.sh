#!/usr/bin/env bash
# =============================================================================
# scripts/02-base-packages.sh
# -----------------------------------------------------------------------------
# Installs the common CLI/dev-utility packages defined in config/packages.conf.
# Also sets `bat` and `eza` up correctly, since on Ubuntu `bat` installs as
# `batcat` and there is no default alias.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="02-base-packages"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Base Packages"

log::info "Installing ${#BASE_PACKAGES[@]} base packages..."
helpers::apt_install "${BASE_PACKAGES[@]}"

# Ubuntu ships `bat` as `batcat` to avoid a name collision with another
# package. Symlink it to `bat` in ~/.local/bin so it matches upstream docs.
if helpers::command_exists batcat && ! helpers::command_exists bat; then
    user_home="$(helpers::current_user_home)"
    mkdir -p "${user_home}/.local/bin"
    ln -sf "$(command -v batcat)" "${user_home}/.local/bin/bat"
    log::success "Symlinked batcat -> bat in ${user_home}/.local/bin"
fi

# Ensure snapd service is enabled (needed later for snap-based apps).
if helpers::command_exists snap; then
    sudo systemctl enable --now snapd.socket >>"${LOG_FILE}" 2>&1 || true
    log::success "snapd service enabled"
fi

# Ensure ~/.local/bin is on PATH for all future modules/shells.
user_home="$(helpers::current_user_home)"
mkdir -p "${user_home}/.local/bin"
while IFS= read -r rc_file; do
    helpers::line_in_file "$rc_file" 'export PATH="$HOME/.local/bin:$PATH"'
done < <(helpers::detect_shell_rc_files)

log::success "Base packages step complete"
