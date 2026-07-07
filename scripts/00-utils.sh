#!/usr/bin/env bash
# =============================================================================
# scripts/00-utils.sh
# -----------------------------------------------------------------------------
# Common bootstrap sourced at the top of every module script (01-*.sh through
# 18-*.sh) and by install.sh itself. Responsible for:
#   - strict-mode shell options
#   - resolving project paths
#   - sourcing lib/*.sh
#   - sourcing config/*.conf
#   - loading .env overrides if present
#   - setting a global ERR trap that logs the failing command + line number
#
# This file is ALWAYS sourced, never executed directly.
# =============================================================================

# Strict mode. Every module inherits this because every module sources this
# file as its very first line.
set -Eeuo pipefail

# Resolve the project root regardless of caller's CWD.
UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVBOOTSTRAP_ROOT="$(cd "${UTILS_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${DEVBOOTSTRAP_ROOT}/lib/colors.sh"
# shellcheck source=/dev/null
source "${DEVBOOTSTRAP_ROOT}/lib/logger.sh"
# shellcheck source=/dev/null
source "${DEVBOOTSTRAP_ROOT}/lib/helpers.sh"
# shellcheck source=/dev/null
source "${DEVBOOTSTRAP_ROOT}/lib/downloads.sh"

# Load configuration (variable assignments only, safe to source).
# shellcheck source=/dev/null
source "${DEVBOOTSTRAP_ROOT}/config/packages.conf"
# shellcheck source=/dev/null
source "${DEVBOOTSTRAP_ROOT}/config/versions.conf"
# shellcheck source=/dev/null
source "${DEVBOOTSTRAP_ROOT}/config/apps.conf"

# Load .env overrides (git name/email, backup dirs, feature toggles) if present.
if [[ -f "${DEVBOOTSTRAP_ROOT}/.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${DEVBOOTSTRAP_ROOT}/.env"
    set +a
fi

# CURRENT_MODULE is used by logger.sh to tag log lines. Each script overrides
# this right after sourcing 00-utils.sh.
CURRENT_MODULE="${CURRENT_MODULE:-utils}"

# -----------------------------------------------------------------------------
# utils::on_error <exit_code> <line_no> <command>
# Global error handler wired up via `trap` in every module script:
#   trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR
# Logs the failure with enough context to debug, but does NOT exit the whole
# installer — modules decide individually whether a failure is fatal via
# their own logic; install.sh continues to the next module on non-zero exit.
# -----------------------------------------------------------------------------
utils::on_error() {
    local exit_code="$1" line_no="$2" command="$3"
    log::error "Command failed (exit ${exit_code}) at line ${line_no}: ${command}"
}

# -----------------------------------------------------------------------------
# utils::require_cmd <cmd> <hint>
# Fails fast with a clear message if a prerequisite command is missing.
# -----------------------------------------------------------------------------
utils::require_cmd() {
    local cmd="$1" hint="${2:-}"
    if ! helpers::command_exists "$cmd"; then
        log::error "Required command '$cmd' not found. ${hint}"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# utils::print_banner <text>
# -----------------------------------------------------------------------------
utils::print_banner() {
    local text="$1"
    echo -e "\n${COLOR_BOLD}${COLOR_MAGENTA}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_MAGENTA} ${text}${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_MAGENTA}════════════════════════════════════════════════════════${COLOR_RESET}\n"
}

export DEVBOOTSTRAP_ROOT CURRENT_MODULE
