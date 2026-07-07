#!/usr/bin/env bash
# =============================================================================
# scripts/06-bun.sh
# -----------------------------------------------------------------------------
# Installs Bun using its official install script, idempotently.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="06-bun"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Bun"
helpers::require_not_root

user_home="$(helpers::current_user_home)"
BUN_INSTALL="${BUN_INSTALL:-${user_home}/.bun}"
export BUN_INSTALL
export PATH="${BUN_INSTALL}/bin:${PATH}"

if helpers::command_exists bun; then
    log::info "Bun already installed: $(bun --version)"
else
    log::info "Installing Bun via official installer..."
    downloads::run_installer_script "https://bun.sh/install"
    export PATH="${BUN_INSTALL}/bin:${PATH}"
    if helpers::command_exists bun; then
        log::success "Bun installed: $(bun --version)"
    else
        log::error "Bun installation could not be verified"
    fi
fi

BUN_BLOCK='export BUN_INSTALL="'"${BUN_INSTALL}"'"
export PATH="$BUN_INSTALL/bin:$PATH"'
while IFS= read -r rc_file; do
    helpers::block_in_file "$rc_file" "bun" "$BUN_BLOCK"
done < <(helpers::detect_shell_rc_files)
log::success "Bun shell integration configured"

log::success "Bun step complete"
