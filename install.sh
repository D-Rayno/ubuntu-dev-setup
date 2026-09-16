#!/usr/bin/env bash
# =============================================================================
# install.sh
# -----------------------------------------------------------------------------
# Entry point for the Ubuntu Developer Environment Bootstrap installer.
# Designed for Ubuntu 24.04 LTS and works on any current/newer Ubuntu release
# (24.10, 25.04, 25.10, 26.04, etc.).
#
# Features:
#   - Interactive package & setup checklist selector (whiptail / console)
#   - Multi-threaded staged parallel execution engine
#   - APT mutex locking for lock-safe concurrent installations
#   - Full AI Agent suite (Antigravity IDE, Antigravity 2.0, Claude Code, Codex)
#   - Samsung SM961 NVMe PCIe ASPM/APST link-drop freeze remediation
#   - Native .deb desktop applications (Chrome, VS Code, Discord, Postman)
#   - Docker non-root permission setup
#   - Enhanced interactive SSH key import, generation, and verification
#
# Usage:
#   ./install.sh                     Interactive checklist selector + parallel install
#   ./install.sh --all               Run every module without showing selector
#   ./install.sh --only 05,09,21     Run only specified modules
#   ./install.sh --skip 11,12        Run everything except given modules
#   ./install.sh --parallel          Enable multi-threaded execution (default)
#   ./install.sh --sequential        Run modules one by one sequentially
#   ./install.sh --force             Ignore past completion states and re-run
#   ./install.sh --reset             Clear all completion state markers
#   ./install.sh --list              List all available modules
#   ./install.sh --dry-run           Display execution plan without running
#   ./install.sh --non-interactive   Use defaults / .env without any prompts
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- Refuse to run as root ---------------------------------------------------
if [[ "${EUID}" -eq 0 ]]; then
    echo "Please do not run install.sh as root or with sudo directly."
    echo "The script will call sudo itself only for the specific commands that need it."
    exit 1
fi

# --- OS detection (soft check) ----------------------------------------------
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

# Source shared utilities, config, and logging
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/scripts/00-utils.sh"
CURRENT_MODULE="install"

# -----------------------------------------------------------------------------
# Module registry
# -----------------------------------------------------------------------------
declare -A MODULE_NAMES=(
    [01]="System Update"
    [02]="Base Packages"
    [03]="Git Configuration"
    [04]="SSH Key Setup (GitHub & GitLab)"
    [05]="Node.js (fnm, npm, pnpm)"
    [06]="Bun Runtime"
    [07]="PHP & Extensions"
    [08]="Composer & Laravel"
    [09]="Docker Engine & Compose (Non-root)"
    [10]="Java (OpenJDK)"
    [11]="Databases (MySQL/PostgreSQL)"
    [12]="Redis"
    [13]="Rust & Cargo"
    [14]="Framework CLIs (Vite, Next, etc.)"
    [15]="Desktop Apps (deb Chrome, VS Code, Discord, Postman)"
    [16]="Hardware Drivers & NVMe Freeze Fix"
    [17]="Shell Configuration"
    [18]="Finalize & Validate"
    [19]="Python 3 & Pipx Tools"
    [20]="Workspace Directory"
    [21]="AI Agents (Antigravity IDE & 2.0, Claude, Codex)"
)

# Standard execution sequence
MODULE_ORDER=(01 02 16 03 04 05 06 19 13 07 08 09 10 11 12 14 15 21 17 20 18)

# --- Argument parsing ---------------------------------------------------------
ONLY_MODULES=""
SKIP_MODULES=""
FROM_MODULE=""
DRY_RUN=0
FORCE_RUN=0
RESET_STATE=0
SELECT_ALL=0
PARALLEL_EXEC=1
ONLY_ARR=()

print_help() {
    sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)
            ONLY_MODULES="$2"; shift 2 ;;
        --skip)
            SKIP_MODULES="$2"; shift 2 ;;
        --from)
            FROM_MODULE="$2"; shift 2 ;;
        --all)
            SELECT_ALL=1; shift ;;
        --parallel)
            PARALLEL_EXEC=1; shift ;;
        --sequential|--no-parallel)
            PARALLEL_EXEC=0; shift ;;
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

if [[ "$RESET_STATE" -eq 1 ]]; then
    rm -f "${LOG_DIR}/.state"/module_*_complete
    echo "Cleared all module completion state. Every module will run fresh on the next ./install.sh."
    exit 0
fi

# --- Build Initial Plan -------------------------------------------------------
PLAN=()
for m in "${MODULE_ORDER[@]}"; do
    PLAN+=("$m")
done

# -----------------------------------------------------------------------------
# Interactive Component Selector (Whiptail dialog with console fallback)
# -----------------------------------------------------------------------------
interactive_select_modules() {
    # Skip if non-interactive, piped input, or explicit flags passed
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]] || [[ ! -t 0 ]] || [[ "$SELECT_ALL" -eq 1 ]]; then
        return 0
    fi
    if [[ -n "$ONLY_MODULES" || -n "$FROM_MODULE" || "$DRY_RUN" -eq 1 ]]; then
        return 0
    fi

    local checklist_items=()
    for m in "${MODULE_ORDER[@]}"; do
        checklist_items+=("$m" "${MODULE_NAMES[$m]}" "ON")
    done

    local selected_output=""
    if helpers::command_exists whiptail; then
        # Open whiptail dialog on stderr/fd3 redirect
        selected_output=$(whiptail --title "Ubuntu Dev Setup - Component Selector" \
            --checklist "Select packages and setups to apply (SPACE to toggle, ENTER to confirm):" \
            26 78 18 "${checklist_items[@]}" 3>&1 1>&2 2>&3 || true)
        selected_output=$(echo "$selected_output" | tr -d '"')
    fi

    # Fallback to pure console menu if whiptail was empty/cancelled or unavailable
    if [[ -z "$selected_output" ]]; then
        echo ""
        echo -e "${COLOR_BOLD}${COLOR_MAGENTA}════════════════════════════════════════════════════════${COLOR_RESET}"
        echo -e "${COLOR_BOLD}${COLOR_MAGENTA} Ubuntu Dev Setup - Component Selector${COLOR_RESET}"
        echo -e "${COLOR_BOLD}${COLOR_MAGENTA}════════════════════════════════════════════════════════${COLOR_RESET}"
        local i=1
        for m in "${MODULE_ORDER[@]}"; do
            printf "  [%2d] %s: %s\n" "$i" "$m" "${MODULE_NAMES[$m]}"
            ((i++))
        done
        echo ""
        echo "Enter selection (e.g. 1-4,6,9,15,21), 'all' for all, or press Enter for default:"
        read -r -p "> " user_choice
        user_choice="${user_choice:-all}"

        if [[ "${user_choice,,}" == "all" ]]; then
            return 0
        fi

        local parsed=()
        IFS=',' read -ra parts <<< "$user_choice"
        for part in "${parts[@]}"; do
            part="$(echo "$part" | xargs)"
            if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                for ((idx=${BASH_REMATCH[1]}; idx<=${BASH_REMATCH[2]}; idx++)); do
                    local m_idx=$((idx - 1))
                    if [[ $m_idx -ge 0 && $m_idx -lt ${#MODULE_ORDER[@]} ]]; then
                        parsed+=("${MODULE_ORDER[$m_idx]}")
                    fi
                done
            elif [[ "$part" =~ ^[0-9]+$ ]]; then
                local m_idx=$((part - 1))
                if [[ $m_idx -ge 0 && $m_idx -lt ${#MODULE_ORDER[@]} ]]; then
                    parsed+=("${MODULE_ORDER[$m_idx]}")
                fi
            fi
        done
        selected_output="${parsed[*]}"
    fi

    if [[ -n "$selected_output" ]]; then
        local new_plan=()
        for m in "${MODULE_ORDER[@]}"; do
            for s in $selected_output; do
                if [[ "$m" == "$s" ]]; then
                    new_plan+=("$m")
                    break
                fi
            done
        done
        if [[ ${#new_plan[@]} -gt 0 ]]; then
            PLAN=("${new_plan[@]}")
        fi
    fi
}

interactive_select_modules

# Apply --from, --only, --skip filter overrides if provided
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

utils::print_banner "Ubuntu Developer Environment Installer"
log::info "Planned modules (${#PLAN[@]} selected, execution: $([[ "$PARALLEL_EXEC" -eq 1 ]] && echo 'parallel multi-threaded' || echo 'sequential')):"
for m in "${PLAN[@]}"; do
    log::info "  ${m} - ${MODULE_NAMES[$m]}"
done

if [[ "$DRY_RUN" -eq 1 ]]; then
    log::info "Dry run requested; exiting without executing any module."
    exit 0
fi

# Make sure sudo is available and cache credentials once up front
if ! command -v sudo >/dev/null 2>&1; then
    echo "This installer requires sudo. Please install sudo and add your user to it first."
    exit 1
fi
echo "This installer needs sudo privileges for system package installation."
sudo -v

# --- Execution Engine ---------------------------------------------------------
FAILED_MODULES=()
SKIPPED_COMPLETED=()
START_TIME=$(date +%s)

install::was_explicitly_requested() {
    local m="$1" o
    for o in "${ONLY_ARR[@]}"; do
        [[ "$m" == "$o" ]] && return 0
    done
    return 1
}

# Executes a single module script
run_module() {
    local m="$1"
    local state_key="module_${m}_complete"

    if [[ "$FORCE_RUN" -eq 0 ]] && ! install::was_explicitly_requested "$m" && helpers::already_done "$state_key"; then
        log::info "Module ${m} (${MODULE_NAMES[$m]}) already completed previously, skipping (use --force to redo)"
        SKIPPED_COMPLETED+=("${m} (${MODULE_NAMES[$m]})")
        return 0
    fi

    local matched_script=""
    for candidate in "${SCRIPT_DIR}/scripts/${m}-"*.sh; do
        [[ -f "$candidate" ]] && matched_script="$candidate"
    done

    if [[ -z "$matched_script" ]]; then
        log::error "No script found for module ${m}. Skipping."
        FAILED_MODULES+=("${m} (${MODULE_NAMES[$m]})")
        return 1
    fi

    utils::print_banner "[Module ${m}] ${MODULE_NAMES[$m]}"
    if bash "$matched_script"; then
        log::success "Module ${m} (${MODULE_NAMES[$m]}) completed"
        helpers::mark_done "$state_key"
        return 0
    else
        log::error "Module ${m} (${MODULE_NAMES[$m]}) failed."
        FAILED_MODULES+=("${m} (${MODULE_NAMES[$m]})")
        return 1
    fi
}

plan_has_module() {
    local target="$1"
    for m in "${PLAN[@]}"; do
        [[ "$m" == "$target" ]] && return 0
    done
    return 1
}

# Sequential execution handler
execute_sequential() {
    for m in "${PLAN[@]}"; do
        run_module "$m" || true
    done
}

# Multi-threaded staged execution handler
execute_parallel() {
    # -------------------------------------------------------------------------
    # Stage 1: System Core & Hardware (01, 02, 16)
    # Prime APT cache, install base build utilities, and apply NVMe freeze fix.
    # -------------------------------------------------------------------------
    for m in 01 02 16; do
        if plan_has_module "$m"; then
            run_module "$m" || true
        fi
    done

    # -------------------------------------------------------------------------
    # Stage 2: Interactive Configuration (03, 04)
    # Run in foreground so git identity & SSH key prompts/clipboard work cleanly.
    # -------------------------------------------------------------------------
    for m in 03 04; do
        if plan_has_module "$m"; then
            run_module "$m" || true
        fi
    done

    # -------------------------------------------------------------------------
    # Stage 3: Independent Toolchain & Application Parallel Streams
    # -------------------------------------------------------------------------
    local active_streams=()
    local stream_names=()

    # Stream 1: Node.js & Framework CLIs
    local s1=()
    plan_has_module 05 && s1+=(05)
    plan_has_module 14 && s1+=(14)
    if [[ ${#s1[@]} -gt 0 ]]; then
        active_streams+=("${s1[*]}")
        stream_names+=("Node.js & Framework CLIs")
    fi

    # Stream 2: Fast Runtimes (Bun, Python, Rust)
    local s2=()
    plan_has_module 06 && s2+=(06)
    plan_has_module 19 && s2+=(19)
    plan_has_module 13 && s2+=(13)
    if [[ ${#s2[@]} -gt 0 ]]; then
        active_streams+=("${s2[*]}")
        stream_names+=("Bun, Python & Rust Runtimes")
    fi

    # Stream 3: PHP & Composer
    local s3=()
    plan_has_module 07 && s3+=(07)
    plan_has_module 08 && s3+=(08)
    if [[ ${#s3[@]} -gt 0 ]]; then
        active_streams+=("${s3[*]}")
        stream_names+=("PHP & Composer")
    fi

    # Stream 4: Services & Backends (Docker, Databases, Redis, Java)
    local s4=()
    plan_has_module 09 && s4+=(09)
    plan_has_module 10 && s4+=(10)
    plan_has_module 11 && s4+=(11)
    plan_has_module 12 && s4+=(12)
    if [[ ${#s4[@]} -gt 0 ]]; then
        active_streams+=("${s4[*]}")
        stream_names+=("Docker, Databases & Java")
    fi

    # Stream 5: Desktop Apps & AI Agents
    local s5=()
    plan_has_module 15 && s5+=(15)
    plan_has_module 21 && s5+=(21)
    if [[ ${#s5[@]} -gt 0 ]]; then
        active_streams+=("${s5[*]}")
        stream_names+=("Desktop Applications & AI Agents")
    fi

    if [[ ${#active_streams[@]} -gt 0 ]]; then
        utils::print_banner "Launching ${#active_streams[@]} Parallel Installation Worker Threads"
        local pids=()
        local stream_idx=0

        for s in "${active_streams[@]}"; do
            local s_title="${stream_names[$stream_idx]}"
            local s_log="${LOG_DIR}/stream_${stream_idx}.log"
            log::info "Starting Worker [${s_title}] (Modules: ${s})..."

            (
                for m in $s; do
                    run_module "$m" || exit 1
                done
            ) > "$s_log" 2>&1 &
            pids+=($!)
            ((stream_idx++))
        done

        # Monitor stream background jobs
        local failed_streams=0
        for i in "${!pids[@]}"; do
            local pid="${pids[$i]}"
            local s_title="${stream_names[$i]}"
            if wait "$pid"; then
                log::success "Worker [${s_title}] completed successfully."
            else
                log::error "Worker [${s_title}] reported errors. Check ${LOG_DIR}/stream_${i}.log."
                failed_streams=$((failed_streams + 1))
            fi
            # Append worker stream log to main install.log
            cat "${LOG_DIR}/stream_${i}.log" >> "${LOG_FILE}" 2>/dev/null || true
        done
    fi

    # -------------------------------------------------------------------------
    # Stage 4: Shell Integration, Workspace & Final Validation
    # -------------------------------------------------------------------------
    for m in 17 20 18; do
        if plan_has_module "$m"; then
            run_module "$m" || true
        fi
    done
}

if [[ "$PARALLEL_EXEC" -eq 1 && ${#PLAN[@]} -gt 2 ]]; then
    execute_parallel
else
    execute_sequential
fi

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

utils::print_banner "Installer Run Summary"
log::info "Total time: $(( ELAPSED / 60 ))m $(( ELAPSED % 60 ))s"

if [[ ${#SKIPPED_COMPLETED[@]} -gt 0 ]]; then
    log::info "Skipped (already completed previously): ${#SKIPPED_COMPLETED[@]} module(s)"
fi

if [[ ${#FAILED_MODULES[@]} -eq 0 ]]; then
    log::success "All selected modules completed successfully."
else
    log::warn "The following modules reported failures:"
    for f in "${FAILED_MODULES[@]}"; do
        log::warn "  - $f"
    done
    log::warn "Check ${ERROR_LOG_FILE} and ${LOG_FILE} for details."
    log::warn "Run ./install.sh again to retry any incomplete modules."
fi

exit 0
