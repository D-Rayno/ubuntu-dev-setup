#!/usr/bin/env bash
# =============================================================================
# scripts/13-rust.sh
# -----------------------------------------------------------------------------
# Installs Rust via rustup (the official installation method), configures
# PATH, and installs a curated set of common cargo utilities.
#
# Toolchain / utility list controlled via config/versions.conf:
#   RUST_TOOLCHAIN, CARGO_UTILS
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="13-rust"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Rust"
helpers::require_not_root

user_home="$(helpers::current_user_home)"
CARGO_HOME="${CARGO_HOME:-${user_home}/.cargo}"
RUSTUP_HOME="${RUSTUP_HOME:-${user_home}/.rustup}"
export CARGO_HOME RUSTUP_HOME
export PATH="${CARGO_HOME}/bin:${PATH}"

if helpers::command_exists rustc; then
    log::info "Rust already installed: $(rustc --version)"
else
    log::info "Installing Rust via rustup (toolchain: ${RUST_TOOLCHAIN})..."
    tmp_script="${DEVBOOTSTRAP_TMP_DIR}/rustup-init.sh"
    downloads::fetch "https://sh.rustup.rs" "$tmp_script"
    chmod +x "$tmp_script"
    "$tmp_script" -y --default-toolchain "$RUST_TOOLCHAIN" --no-modify-path >>"${LOG_FILE}" 2>&1
    export PATH="${CARGO_HOME}/bin:${PATH}"
    log::success "Rust installed: $(rustc --version)"
fi

RUST_BLOCK='export CARGO_HOME="'"${CARGO_HOME}"'"
export RUSTUP_HOME="'"${RUSTUP_HOME}"'"
export PATH="$CARGO_HOME/bin:$PATH"'
while IFS= read -r rc_file; do
    helpers::block_in_file "$rc_file" "rust" "$RUST_BLOCK"
done < <(helpers::detect_shell_rc_files)
log::success "Rust shell integration configured"

log::info "Ensuring toolchain '${RUST_TOOLCHAIN}' is installed and default..."
rustup toolchain install "$RUST_TOOLCHAIN" >>"${LOG_FILE}" 2>&1
rustup default "$RUST_TOOLCHAIN" >>"${LOG_FILE}" 2>&1

log::info "Installing cargo utilities: ${CARGO_UTILS}"
for util in $CARGO_UTILS; do
    bin_name="${util#cargo-}"
    if cargo "${bin_name}" --version >/dev/null 2>&1; then
        log::debug "cargo utility '${util}' already installed"
    else
        log::info "Installing ${util}..."
        cargo install "$util" >>"${LOG_FILE}" 2>&1 && log::success "${util} installed" || log::warn "Failed to install ${util}"
    fi
done

log::success "Rust step complete: $(rustc --version), $(cargo --version)"
