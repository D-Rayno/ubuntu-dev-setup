#!/usr/bin/env bash
# =============================================================================
# scripts/18-finalize.sh
# -----------------------------------------------------------------------------
# Runs a final validation pass across every tool the installer touched and
# prints a clean summary table so it's obvious at a glance what succeeded,
# what's missing, and what needs a reboot / shell restart to take effect.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="18-finalize"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Finalizing & Validating Installation"

# Bring fnm/cargo/bun/composer paths into this script's PATH so
# validation reflects reality even in a single non-restarted shell.
user_home="$(helpers::current_user_home)"
export PATH="${user_home}/.local/bin:${user_home}/.bun/bin:${user_home}/.cargo/bin:${PATH}"
export FNM_DIR="${user_home}/.local/share/fnm"
export PATH="${FNM_DIR}:${PATH}"
helpers::command_exists fnm && eval "$(fnm env --shell bash)" || true

declare -a RESULTS=()

# -----------------------------------------------------------------------------
# finalize::check <label> <command...>
# Runs <command>, records pass/fail plus first line of output for the summary.
# -----------------------------------------------------------------------------
finalize::check() {
    local label="$1"; shift
    local output status
    if output="$("$@" 2>&1)"; then
        status="OK"
    else
        status="MISSING"
        output="not found / failed"
    fi
    local first_line
    first_line="$(echo "$output" | head -n1)"
    RESULTS+=("${status}|${label}|${first_line}")
}

finalize::check "Git"          git --version
finalize::check "SSH client"   ssh -V
finalize::check "Node.js"      node -v
finalize::check "npm"          npm -v
finalize::check "pnpm"         pnpm --version
finalize::check "Bun"          bun --version
finalize::check "PHP"          php -v
finalize::check "Composer"     composer --version
finalize::check "Docker"       docker --version
finalize::check "Docker Compose" docker compose version
finalize::check "Java"         java -version
finalize::check "MySQL"        mysql --version
finalize::check "PostgreSQL"   psql --version
finalize::check "Redis"        redis-cli --version
finalize::check "Rust"         rustc --version
finalize::check "Cargo"        cargo --version
finalize::check "Python 3"     python3 --version
finalize::check "pip"          python3 -m pip --version
finalize::check "pipx"         pipx --version
finalize::check "TypeScript"   tsc --version
finalize::check "ESLint"       eslint --version
finalize::check "Vite"         vite --version
finalize::check "NestJS CLI"   nest --version
finalize::check "Google Chrome" google-chrome --version
finalize::check "VS Code"      code --version

user_home_check="$(helpers::current_user_home)"
workspace_check_dir="${WORKSPACE_DIR/#\~/$user_home_check}"
finalize::check "Workspace dir" test -d "$workspace_check_dir"

echo ""
printf "%-10s %-20s %-40s\n" "STATUS" "TOOL" "VERSION / NOTE"
printf '%.0s-' {1..72}; echo ""
for entry in "${RESULTS[@]}"; do
    IFS='|' read -r status label note <<< "$entry"
    if [[ "$status" == "OK" ]]; then
        color="${COLOR_GREEN}"
    else
        color="${COLOR_YELLOW}"
    fi
    printf "${color}%-10s${COLOR_RESET} %-20s %-40s\n" "$status" "$label" "$note"
    log::_write_file "$status" "${label}: ${note}"
done
echo ""

helpers::mark_done "install_completed_$(date +%Y%m%d_%H%M%S)"

utils::print_banner "Installation Complete"

cat <<EOF
${COLOR_BOLD}Next steps:${COLOR_RESET}

  1. Restart your terminal (or run: exec \$SHELL -l) so all PATH and shell
     integration changes (fnm, bun, rust, composer, Java) take effect.

  2. If Docker was newly installed, log out and back in (or run
     'newgrp docker') for your user's docker-group membership to apply.

  3. If an NVIDIA driver was installed, reboot before relying on it.

  4. Review ${LOG_FILE} for the full run log, and ${ERROR_LOG_FILE} for any
     warnings/errors that occurred along the way.

  5. Re-run ./install.sh any time — every module is idempotent and will
     skip work that's already done.

EOF

log::success "All modules finished. See summary above."
