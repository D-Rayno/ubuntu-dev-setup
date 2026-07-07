#!/usr/bin/env bash
# =============================================================================
# scripts/08-composer.sh
# -----------------------------------------------------------------------------
# Installs Composer globally following the official installation instructions
# from getcomposer.org, including installer signature verification.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="08-composer"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Composer"

utils::require_cmd php "Run scripts/07-php.sh first."

if helpers::command_exists composer; then
    log::info "Composer already installed: $(composer --version 2>/dev/null)"
else
    log::info "Downloading Composer installer and verifying signature..."
    tmp_dir="${DEVBOOTSTRAP_TMP_DIR}/composer"
    mkdir -p "$tmp_dir"
    cd "$tmp_dir" || { log::error "Could not enter ${tmp_dir}"; exit 1; }

    EXPECTED_SIGNATURE="$(curl -fsSL https://composer.github.io/installer.sig)"
    curl -fsSL -o composer-setup.php https://getcomposer.org/installer

    ACTUAL_SIGNATURE="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [[ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]]; then
        log::error "Composer installer signature mismatch! Aborting installation for safety."
        rm -f composer-setup.php
        exit 1
    fi
    log::success "Composer installer signature verified"

    sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer >>"${LOG_FILE}" 2>&1
    rm -f composer-setup.php
    cd - >/dev/null || true

    log::success "Composer installed: $(composer --version)"
fi

# /usr/local/bin is on PATH by default on Ubuntu, but make sure user-level
# global composer packages are reachable too.
user_home="$(helpers::current_user_home)"
COMPOSER_GLOBAL_BIN="${user_home}/.config/composer/vendor/bin"
while IFS= read -r rc_file; do
    helpers::line_in_file "$rc_file" "export PATH=\"${COMPOSER_GLOBAL_BIN}:\$PATH\""
done < <(helpers::detect_shell_rc_files)

log::info "Checking Laravel Installer (global Composer package)..."
if composer global show laravel/installer >/dev/null 2>&1; then
    log::info "Laravel Installer already installed globally, skipping (no forced update)."
else
    log::info "Installing Laravel Installer globally via Composer..."
    composer global require laravel/installer >>"${LOG_FILE}" 2>&1 \
        && log::success "Laravel Installer installed" \
        || log::warn "Laravel installer via composer failed; will also be attempted in 14-frameworks.sh"
fi

log::success "Composer step complete"
