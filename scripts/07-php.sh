#!/usr/bin/env bash
# =============================================================================
# scripts/07-php.sh
# -----------------------------------------------------------------------------
# Installs PHP via the official Sury repository (packages.sury.org/php), per
# the installation instructions published at php.net/downloads and
# deb.sury.org — this is the officially documented source for modern PHP
# versions on Debian/Ubuntu, using a deb822-format .sources file and the
# distro-packaged keyring (debsuryorg-archive-keyring).
#
# Installs every version listed in PHP_VERSIONS (config/versions.conf) side
# by side with a common set of extensions, and configures update-alternatives
# so `php` points at PHP_DEFAULT_VERSION.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="07-php"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "PHP"

helpers::apt_install lsb-release ca-certificates curl

PHP_SOURCES_FILE="/etc/apt/sources.list.d/php.sources"
PHP_KEYRING="/usr/share/keyrings/debsuryorg-archive-keyring.gpg"

if [[ -f "$PHP_SOURCES_FILE" ]] && helpers::is_installed debsuryorg-archive-keyring; then
    log::info "packages.sury.org/php repository already configured"
else
    log::info "Adding the official Sury PHP repository (packages.sury.org/php)..."

    # The keyring is shipped as its own .deb by Sury so apt can verify it
    # was signed by the correct key, rather than us dearmoring a raw key.
    if ! helpers::is_installed debsuryorg-archive-keyring; then
        tmp_keyring_deb="${DEVBOOTSTRAP_TMP_DIR}/debsuryorg-archive-keyring.deb"
        downloads::fetch "https://packages.sury.org/debsuryorg-archive-keyring.deb" "$tmp_keyring_deb"
        sudo dpkg -i "$tmp_keyring_deb" >>"${LOG_FILE}" 2>&1
        rm -f "$tmp_keyring_deb"
        log::success "debsuryorg-archive-keyring installed"
    fi

    # Modern deb822 .sources format, exactly as documented by Sury/php.net.
    UBUNTU_CODENAME="$(lsb_release -sc)"
    sudo tee "$PHP_SOURCES_FILE" >/dev/null <<EOF
Types: deb
URIs: https://packages.sury.org/php/
Suites: ${UBUNTU_CODENAME}
Components: main
Signed-By: ${PHP_KEYRING}
EOF
    log::success "Wrote ${PHP_SOURCES_FILE} for suite '${UBUNTU_CODENAME}'"

    rm -f "/tmp/.devbootstrap_apt_updated_$(date +%Y%m%d)"
    helpers::apt_update_once
fi

PHP_EXTENSIONS=(
    cli fpm mysql pgsql sqlite3 curl xml mbstring zip gd intl bcmath soap
    opcache redis imagick common
)

for version in $PHP_VERSIONS; do
    log::step "Installing PHP ${version}"
    pkgs=()
    for ext in "${PHP_EXTENSIONS[@]}"; do
        pkgs+=("php${version}-${ext}")
    done
    # php{version}-cli's base metapackage is just "phpX.Y"; include it too.
    pkgs+=("php${version}")
    helpers::apt_install "${pkgs[@]}"
    log::success "PHP ${version} installed with extensions: ${PHP_EXTENSIONS[*]}"
done

log::info "Setting PHP ${PHP_DEFAULT_VERSION} as the default 'php' CLI via update-alternatives..."
for version in $PHP_VERSIONS; do
    php_bin="/usr/bin/php${version}"
    if [[ -x "$php_bin" ]]; then
        priority=$(( ${version//./} ))
        sudo update-alternatives --install /usr/bin/php php "$php_bin" "$priority" >>"${LOG_FILE}" 2>&1 || true
    fi
done
sudo update-alternatives --set php "/usr/bin/php${PHP_DEFAULT_VERSION}" >>"${LOG_FILE}" 2>&1 || \
    log::warn "Could not set default PHP alternative automatically; run 'sudo update-alternatives --config php' manually."

log::success "Active php CLI: $(php -v | head -n1 2>/dev/null || echo 'unavailable')"

cat <<'EOF' | while IFS= read -r line; do log::info "$line"; done
Tip: switch the active CLI PHP version any time with:
  sudo update-alternatives --config php
EOF

log::success "PHP step complete"
