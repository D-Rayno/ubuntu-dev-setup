#!/usr/bin/env bash
# =============================================================================
# install.sh
# -----------------------------------------------------------------------------
# Entry point for the Ubuntu Developer Environment Bootstrap installer.
# Designed for Ubuntu 24.04 LTS and works on any current/newer Ubuntu release
# (24.10, 25.04, 25.10, 26.04, etc.) — every module detects the release
# codename/version at runtime instead of hardcoding one, and apt installs
# gracefully skip any individual package that doesn't exist on your release
# instead of aborting the whole module.
#
# Usage:
#   ./install.sh                     Run every module, auto-skipping any that
#                                     already completed successfully in a
#                                     previous run (this is what makes a
#                                     crashed run "just continue" if you
#                                     simply run ./install.sh again)
#   ./install.sh --only 05,06,09     Force-run only the specified modules,
#                                     even if they were already completed
#   ./install.sh --skip 16           Run everything except the given modules
#   ./install.sh --from 09           Resume starting at a given module
#   ./install.sh --force             Ignore completion state; re-run every
#                                     planned module regardless of past runs
#   ./install.sh --reset             Clear all "completed" state and exit
#                                     (run this if you want a clean slate)
#   ./install.sh --list               List all available modules and exit
#   ./install.sh --verbose            Enable debug-level logging
#   ./install.sh --non-interactive    Never prompt; use defaults / .env values
#   ./install.sh --dry-run            Print the module plan without running it
#   ./install.sh -h | --help          Show this help text
#
# Safe to re-run at any time: every module is designed to be idempotent, and
# completed modules are tracked in logs/.state/ so a crashed run (e.g. lost
# network mid-install) picks back up exactly where it left off the next time
# you run ./install.sh — no flags needed.
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Refuse to run as root ---------------------------------------------------
# Several tools (fnm, bun, rustup) install into the invoking user's
# home directory and must NOT be installed as root. Individual apt/system
# steps use `sudo` internally instead.
if [[ "${EUID}" -eq 0 ]]; then
    echo "Please do not run install.sh as root or with sudo directly."
    echo "The script will call sudo itself only for the specific commands that need it."
    exit 1
fi

# --- OS detection (soft check) ----------------------------------------------
# We target Ubuntu but don't hard-fail on anything else — a warning lets
# people on Ubuntu derivatives (or a Debian base) proceed at their own risk
# instead of being blocked outright.
if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    DETECTED_OS_ID="${ID:-unknown}"
    DETECTED_OS_VERSION="${VERSION_ID:-unknown}"
    DETECTED_OS_NAME="${PRETTY_NAME:-unknown}"
else
    DETECTED_OS_ID="unknown"
    DETECTED_OS_VERSION="unknown"
    DETECTED_OS_NAME="unknown"
fi

if [[ "$DETECTED_OS_ID" != "ubuntu" ]]; then
    echo "Warning: this installer is designed for Ubuntu. Detected: ${DETECTED_OS_NAME}."
    echo "Continuing anyway — some modules may not work correctly on non-Ubuntu systems."
else
    echo "Detected: ${DETECTED_OS_NAME}"
fi

# Make sure sudo is available and cache credentials once up front so later
# modules don't repeatedly prompt for a password mid-run.
if ! command -v sudo >/dev/null 2>&1; then
    echo "This installer requires sudo. Please install sudo and add your user to it first."
    exit 1
fi
echo "This installer needs sudo privileges for system package installation."
sudo -v

# Source shared libs/config now so install.sh itself has logging/helpers too.
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/scripts/00-utils.sh"
CURRENT_MODULE="install"

# -----------------------------------------------------------------------------
# Module registry: order matters. Keep numbers zero-padded and sequential;
# see README.md "Adding a new module" for how to extend this list.
# -----------------------------------------------------------------------------
declare -A MODULE_NAMES=(
    [01]="System Update"
    [02]="Base Packages"
    [03]="Git"
    [04]="SSH"
    [05]="Node.js (fnm)"
    [06]="Bun"
    [07]="PHP"
    [08]="Composer"
    [09]="Docker"
    [10]="Java (OpenJDK)"
    [11]="Databases (MySQL/PostgreSQL)"
    [12]="Redis"
    [13]="Rust"
    [14]="Framework CLIs"
    [15]="Desktop Applications"
    [16]="NVIDIA Drivers"
    [17]="Shell Configuration"
    [18]="Finalize & Validate"
    [19]="Python 3"
    [20]="Workspace Directory"
)
MODULE_ORDER=(01 02 03 04 05 06 07 08 09 10 11 12 13 14 19 15 20 16 17 18)

# --- Argument parsing ---------------------------------------------------------
ONLY_MODULES=""
SKIP_MODULES=""
FROM_MODULE=""
DRY_RUN=0
FORCE_RUN=0
RESET_STATE=0
ONLY_ARR=()

print_help() {
    sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)
            ONLY_MODULES="$2"; shift 2 ;;
        --skip)
            SKIP_MODULES="$2"; shift 2 ;;
        --from)
            FROM_MODULE="$2"; shift 2 ;;
        --force)
            FORCE_RUN=1; shift ;;
        --reset)
            RESET_STATE=1; shift ;;
        --list)
            echo "Available modules:"
            for m in "${MODULE_ORDER[@]}"; do
                printf "  %s  %s\n" "$m" "${MODULE_NAMES[$m]}"
            done
            exit 0 ;;
        --verbose|-v)
            export VERBOSE=1; shift ;;
        --non-interactive)
            export NON_INTERACTIVE=1; shift ;;
        --dry-run)
            DRY_RUN=1; shift ;;
        -h|--help)
            print_help; exit 0 ;;
        *)
            echo "Unknown argument: $1"
            print_help
            exit 1 ;;
    esac
done

# --reset clears all "module completed" markers so the next run (this one,
# or a future one) starts completely fresh, then exits — it's a standalone
# action, not something you'd combine with actually running modules.
if [[ "$RESET_STATE" -eq 1 ]]; then
    rm -f "${LOG_DIR}/.state"/module_*_complete
    echo "Cleared all module completion state. Every module will run fresh on the next ./install.sh."
    exit 0
fi

# --- Build the effective module plan -----------------------------------------
PLAN=()
for m in "${MODULE_ORDER[@]}"; do
    PLAN+=("$m")
done

if [[ -n "$FROM_MODULE" ]]; then
    NEW_PLAN=()
    started=0
    for m in "${PLAN[@]}"; do
        [[ "$m" == "$FROM_MODULE" ]] && started=1
        [[ "$started" -eq 1 ]] && NEW_PLAN+=("$m")
    done
    PLAN=("${NEW_PLAN[@]}")
fi

if [[ -n "$ONLY_MODULES" ]]; then
    IFS=',' read -ra ONLY_ARR <<< "$ONLY_MODULES"
    NEW_PLAN=()
    for m in "${PLAN[@]}"; do
        for o in "${ONLY_ARR[@]}"; do
            [[ "$m" == "$o" ]] && NEW_PLAN+=("$m")
        done
    done
    PLAN=("${NEW_PLAN[@]}")
fi
if [[ -n "$SKIP_MODULES" ]]; then
    IFS=',' read -ra SKIP_ARR <<< "$SKIP_MODULES"
    NEW_PLAN=()
    for m in "${PLAN[@]}"; do
        skip_this=0
        for s in "${SKIP_ARR[@]}"; do
            [[ "$m" == "$s" ]] && skip_this=1
        done
        [[ "$skip_this" -eq 0 ]] && NEW_PLAN+=("$m")
    done
    PLAN=("${NEW_PLAN[@]}")
fi

utils::print_banner "Ubuntu 24.04 LTS Developer Environment Installer"
log::info "Planned modules (in order):"
for m in "${PLAN[@]}"; do
    log::info "  ${m} - ${MODULE_NAMES[$m]}"
done

if [[ "$DRY_RUN" -eq 1 ]]; then
    log::info "Dry run requested; exiting without executing any module."
    exit 0
fi

# --- Execute the plan ---------------------------------------------------------
FAILED_MODULES=()
SKIPPED_COMPLETED=()
START_TIME=$(date +%s)

# -----------------------------------------------------------------------------
# install::was_explicitly_requested <module_number>
# True if the module was named directly via --only — an explicit request
# always runs, even if it was already marked complete in a previous run.
# -----------------------------------------------------------------------------
install::was_explicitly_requested() {
    local m="$1" o
    for o in "${ONLY_ARR[@]}"; do
        [[ "$m" == "$o" ]] && return 0
    done
    return 1
}

for m in "${PLAN[@]}"; do
    state_key="module_${m}_complete"

    # Skip a module that already completed successfully in a previous run,
    # UNLESS: --force was passed, or this exact module was explicitly named
    # via --only. This is what makes a crashed run "just continue" — running
    # ./install.sh again skips everything already done and picks back up at
    # the module that failed (or never got to run).
    if [[ "$FORCE_RUN" -eq 0 ]] && ! install::was_explicitly_requested "$m" && helpers::already_done "$state_key"; then
        log::info "Module ${m} (${MODULE_NAMES[$m]}) already completed previously, skipping (use --force to redo)"
        SKIPPED_COMPLETED+=("${m} (${MODULE_NAMES[$m]})")
        continue
    fi

    # Glob expansion: find the actual filename matching the module number prefix.
    matched_script=""
    for candidate in "${SCRIPT_DIR}/scripts/${m}-"*.sh; do
        [[ -f "$candidate" ]] && matched_script="$candidate"
    done

    if [[ -z "$matched_script" ]]; then
        log::error "No script found for module ${m}. Skipping."
        FAILED_MODULES+=("${m} (${MODULE_NAMES[$m]})")
        continue
    fi

    utils::print_banner "[Module ${m}] ${MODULE_NAMES[$m]}"
    if bash "$matched_script"; then
        log::success "Module ${m} (${MODULE_NAMES[$m]}) completed"
        helpers::mark_done "$state_key"
    else
        log::error "Module ${m} (${MODULE_NAMES[$m]}) failed. Continuing with next module."
        log::warn "Module ${m} was NOT marked complete — running ./install.sh again will retry it."
        FAILED_MODULES+=("${m} (${MODULE_NAMES[$m]})")
    fi
done

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

utils::print_banner "Installer Run Summary"
log::info "Total time: $(( ELAPSED / 60 ))m $(( ELAPSED % 60 ))s"

if [[ ${#SKIPPED_COMPLETED[@]} -gt 0 ]]; then
    log::info "Skipped (already completed previously): ${#SKIPPED_COMPLETED[@]} module(s)"
fi

if [[ ${#FAILED_MODULES[@]} -eq 0 ]]; then
    log::success "All modules completed successfully."
else
    log::warn "The following modules reported failures:"
    for f in "${FAILED_MODULES[@]}"; do
        log::warn "  - $f"
    done
    log::warn "Check ${ERROR_LOG_FILE} for details."
    log::warn "Just run ./install.sh again — completed modules are skipped automatically,"
    log::warn "and it will retry exactly the module(s) that failed above."
fi

exit 0
