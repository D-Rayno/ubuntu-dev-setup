#!/usr/bin/env bash
# =============================================================================
# lib/logger.sh
# -----------------------------------------------------------------------------
# Centralized logging for the installer.
#
# Every module sources this file (indirectly, via 00-utils.sh) and gets:
#   log::info    "message"
#   log::warn    "message"
#   log::error   "message"
#   log::success "message"
#   log::debug   "message"      (only prints when VERBOSE=1)
#   log::step    "message"      (section headers)
#
# All messages are written to logs/install.log. Anything logged with
# log::error / log::warn is additionally written to logs/error.log so that
# problems are easy to find after a long run.
#
# Log directory / files are created lazily on first use.
# =============================================================================

if [[ -n "${__DEVBOOTSTRAP_LOGGER_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
__DEVBOOTSTRAP_LOGGER_LOADED=1

# Resolve project root relative to this file so logging works no matter which
# script sources it (scripts/, root install.sh, etc).
_LOGGER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVBOOTSTRAP_ROOT="$(cd "${_LOGGER_LIB_DIR}/.." && pwd)"
LOG_DIR="${DEVBOOTSTRAP_ROOT}/logs"
LOG_FILE="${LOG_DIR}/install.log"
ERROR_LOG_FILE="${LOG_DIR}/error.log"

mkdir -p "${LOG_DIR}"
touch "${LOG_FILE}" "${ERROR_LOG_FILE}"

# VERBOSE=1 enables log::debug output. Set via ./install.sh -v or --verbose.
VERBOSE="${VERBOSE:-0}"

# Internal: timestamp helper.
log::_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Internal: writes a raw line to the main log file (no colors).
log::_write_file() {
    local level="$1" msg="$2"
    printf '[%s] [%-7s] [%s] %s\n' "$(log::_timestamp)" "$level" "${CURRENT_MODULE:-install}" "$msg" >> "${LOG_FILE}"
}

log::info() {
    local msg="$1"
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET}    ${msg}"
    log::_write_file "INFO" "$msg"
}

log::success() {
    local msg="$1"
    echo -e "${COLOR_GREEN}[ OK ]${COLOR_RESET}    ${msg}"
    log::_write_file "SUCCESS" "$msg"
}

log::warn() {
    local msg="$1"
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET}    ${msg}" >&2
    log::_write_file "WARN" "$msg"
    printf '[%s] [%-7s] [%s] %s\n' "$(log::_timestamp)" "WARN" "${CURRENT_MODULE:-install}" "$msg" >> "${ERROR_LOG_FILE}"
}

log::error() {
    local msg="$1"
    echo -e "${COLOR_RED}[FAIL]${COLOR_RESET}    ${msg}" >&2
    log::_write_file "ERROR" "$msg"
    printf '[%s] [%-7s] [%s] %s\n' "$(log::_timestamp)" "ERROR" "${CURRENT_MODULE:-install}" "$msg" >> "${ERROR_LOG_FILE}"
}

log::debug() {
    local msg="$1"
    if [[ "${VERBOSE}" == "1" ]]; then
        echo -e "${COLOR_DIM}[DBG ]    ${msg}${COLOR_RESET}"
    fi
    log::_write_file "DEBUG" "$msg"
}

log::step() {
    local msg="$1"
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_CYAN}==> ${msg}${COLOR_RESET}"
    log::_write_file "STEP" "=== ${msg} ==="
}

export LOG_DIR LOG_FILE ERROR_LOG_FILE VERBOSE DEVBOOTSTRAP_ROOT
