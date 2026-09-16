#!/usr/bin/env bash
# =============================================================================
# scripts/05-fnm-node.sh
# -----------------------------------------------------------------------------
# Installs fnm (Fast Node Manager), configures shell integration, installs
# Node LTS, npm, Corepack, and pnpm — but ONLY on first install. Once Node,
# npm, and pnpm are present, this module leaves them alone on every
# subsequent run instead of force-upgrading them — that's what apt-get
# upgrade in module 01 is for at the system level; per-tool version bumps
# here should be something you opt into, not something that happens as a
# side effect of re-running the installer.
#
# To deliberately upgrade Node/npm/pnpm later, either bump NODE_LTS_ALIAS /
# PNPM_VERSION in config/versions.conf and run `./install.sh --force --only 05`,
# or just use fnm/corepack directly (fnm install --lts, corepack prepare
# pnpm@latest --activate).
#
# Node version controlled via config/versions.conf: NODE_LTS_ALIAS
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="05-fnm-node"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Node.js (fnm)"
helpers::require_not_root

user_home="$(helpers::current_user_home)"
FNM_DIR="${FNM_DIR:-${user_home}/.local/share/fnm}"
export FNM_DIR
export PATH="${FNM_DIR}:${PATH}"

if helpers::command_exists fnm; then
    log::info "fnm already installed: $(fnm --version)"
else
    log::info "Installing fnm..."
    downloads::run_installer_script "https://fnm.vercel.app/install" --install-dir "${FNM_DIR}" --skip-shell
    export PATH="${FNM_DIR}:${PATH}"
    log::success "fnm installed"
fi

# Configure shell integration idempotently for both bash and zsh.
FNM_BLOCK='export PATH="'"${FNM_DIR}"':$PATH"
eval "$(fnm env --use-on-cd --shell bash 2>/dev/null || true)"'
while IFS= read -r rc_file; do
    if [[ "$rc_file" == *zshrc ]]; then
        helpers::block_in_file "$rc_file" "fnm" 'export PATH="'"${FNM_DIR}"':$PATH"
eval "$(fnm env --use-on-cd --shell zsh)"'
    else
        helpers::block_in_file "$rc_file" "fnm" "$FNM_BLOCK"
    fi
done < <(helpers::detect_shell_rc_files)
log::success "fnm shell integration configured"

# Make fnm's shims available to this (non-interactive) script.
eval "$(fnm env --shell bash)"

# -----------------------------------------------------------------------------
# Node.js: only install if no active Node version is already selected via
# fnm. If Node is already present, we leave the version alone entirely —
# no re-install, no forced upgrade to a newer LTS on every run.
# -----------------------------------------------------------------------------
if helpers::command_exists node; then
    log::info "Node.js already installed and active: $(node -v). Skipping install (no forced upgrade)."
else
    log::info "Installing Node ${NODE_LTS_ALIAS}..."
    fnm install --lts >>"${LOG_FILE}" 2>&1
    fnm default lts-latest >>"${LOG_FILE}" 2>&1
    fnm use lts-latest >>"${LOG_FILE}" 2>&1
    eval "$(fnm env --shell bash)"
    log::success "Node.js installed and active: $(node -v)"
fi

# -----------------------------------------------------------------------------
# npm: ships bundled with Node, so it always exists once Node is installed.
# We only force it to a specific/newer version on the initial install of
# this module (tracked via a state marker) — after that, npm is left alone
# so re-running the installer never silently bumps its version.
# -----------------------------------------------------------------------------
if helpers::already_done "npm_initial_setup"; then
    log::info "npm already set up previously: $(npm -v). Skipping (no forced upgrade)."
else
    log::info "Updating npm to latest (first-time setup only)..."
    npm install -g npm@latest >>"${LOG_FILE}" 2>&1
    helpers::mark_done "npm_initial_setup"
    log::success "npm ready: $(npm -v)"
fi

# Disable Corepack interactive download prompt to prevent hanging in non-interactive scripts
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
while IFS= read -r rc_file; do
    helpers::line_in_file "$rc_file" 'export COREPACK_ENABLE_DOWNLOAD_PROMPT=0'
done < <(helpers::detect_shell_rc_files)

log::info "Configuring Corepack..."
corepack enable >>"${LOG_FILE}" 2>&1 || log::warn "corepack enable reported an issue (non-fatal)"

# -----------------------------------------------------------------------------
# pnpm: install reliably via npm (avoids Corepack signature verification hangs)
# and ensure it is available globally.
# -----------------------------------------------------------------------------
if helpers::command_exists pnpm; then
    log::info "pnpm already installed: $(pnpm --version 2>/dev/null || echo 'ready'). Skipping."
else
    log::info "Installing pnpm (version: ${PNPM_VERSION})..."
    if [[ "$PNPM_VERSION" == "latest" ]]; then
        npm install -g pnpm@latest >>"${LOG_FILE}" 2>&1 || corepack prepare pnpm@latest --activate >>"${LOG_FILE}" 2>&1
    else
        npm install -g "pnpm@${PNPM_VERSION}" >>"${LOG_FILE}" 2>&1 || corepack prepare "pnpm@${PNPM_VERSION}" --activate >>"${LOG_FILE}" 2>&1
    fi
    log::success "pnpm ready: $(pnpm --version 2>/dev/null || echo 'installed')"
fi

log::success "Node.js / fnm step complete"
