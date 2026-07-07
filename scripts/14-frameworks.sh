#!/usr/bin/env bash
# =============================================================================
# scripts/14-frameworks.sh
# -----------------------------------------------------------------------------
# Installs commonly used frontend/backend framework CLIs and dev tooling
# globally via npm (Node must already be installed by 05-fnm-node.sh), plus
# the Laravel installer via Composer and Tauri's CLI prerequisites.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="14-frameworks"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Framework CLIs & Dev Tooling"

# Make sure fnm-managed node/npm are on PATH for this script.
user_home="$(helpers::current_user_home)"
export FNM_DIR="${FNM_DIR:-${user_home}/.local/share/fnm}"
export PATH="${FNM_DIR}:${PATH}"
if helpers::command_exists fnm; then
    eval "$(fnm env --shell bash)"
fi

utils::require_cmd npm "Run scripts/05-fnm-node.sh first."

# -----------------------------------------------------------------------------
# npm_global_install <package> [package...]
# Installs global npm packages, skipping ones already present.
# -----------------------------------------------------------------------------
npm_global_install() {
    local to_install=()
    local pkg
    for pkg in "$@"; do
        local bare_name="${pkg%%@*}"
        if npm ls -g --depth=0 2>/dev/null | grep -q "${bare_name}@"; then
            log::debug "npm global package '${bare_name}' already installed"
        else
            to_install+=("$pkg")
        fi
    done
    if [[ ${#to_install[@]} -eq 0 ]]; then
        return 0
    fi
    log::info "npm install -g ${to_install[*]}"
    npm install -g "${to_install[@]}" >>"${LOG_FILE}" 2>&1 && log::success "Installed: ${to_install[*]}" \
        || log::warn "Some packages failed to install: ${to_install[*]} (see ${LOG_FILE})"
}

log::step "Core web tooling"
npm_global_install typescript eslint prettier npm-check-updates

log::step "Build tools & monorepo tooling"
npm_global_install vite turbo nx

log::step "Frontend framework CLIs"
npm_global_install @vue/cli create-vue @angular/cli create-next-app nuxi

log::step "Backend / full-stack framework CLIs"
npm_global_install @nestjs/cli

log::step "Cross-platform / mobile"
npm_global_install @tauri-apps/cli expo-cli eas-cli react-native-cli @react-native-community/cli

log::step "Laravel installer (PHP / Composer)"
if helpers::command_exists composer; then
    if composer global show laravel/installer >/dev/null 2>&1; then
        log::info "Laravel Installer already installed globally, skipping (no forced update)."
    else
        composer global require laravel/installer >>"${LOG_FILE}" 2>&1 \
            && log::success "Laravel installer ready via composer" \
            || log::warn "Laravel installer install via composer reported an issue"
    fi
else
    log::warn "Composer not found; skipping Laravel installer. Run scripts/08-composer.sh first."
fi

log::success "Framework CLIs step complete"
