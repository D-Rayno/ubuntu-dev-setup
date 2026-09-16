#!/usr/bin/env bash
# =============================================================================
# lib/helpers.sh
# -----------------------------------------------------------------------------
# Reusable helper functions shared by every module. Keeping these in one
# place avoids duplicated logic across scripts/*.sh and is the main way we
# guarantee idempotency (helpers always check "is this already done?"
# before doing it).
#
# Depends on: colors.sh, logger.sh (both must already be sourced).
# =============================================================================

if [[ -n "${__DEVBOOTSTRAP_HELPERS_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
__DEVBOOTSTRAP_HELPERS_LOADED=1

# NON_INTERACTIVE=1 disables all prompts and falls back to sane defaults.
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"

# -----------------------------------------------------------------------------
# helpers::command_exists <cmd>
# Returns 0 if <cmd> is available on PATH.
# -----------------------------------------------------------------------------
helpers::command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# helpers::is_installed <apt-package-name>
# Returns 0 if the given apt package is already installed.
# -----------------------------------------------------------------------------
helpers::is_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# helpers::with_apt_lock <command...>
# Runs an apt/dpkg command wrapped in a file lock to guarantee mutual
# exclusion across parallel worker threads.
# -----------------------------------------------------------------------------
helpers::with_apt_lock() {
    local lock_file="/tmp/.devbootstrap_apt.flock"
    # Acquire lock with a 300s timeout
    (
        flock -x -w 300 200 || {
            log::error "Could not acquire devbootstrap apt lock within 300s."
            return 1
        }
        "$@"
    ) 200>"$lock_file"
}

# -----------------------------------------------------------------------------
# helpers::wait_for_apt_lock
# Waits for any external package managers (e.g. unattended-upgrades) to release
# dpkg locks before initiating an operation.
# -----------------------------------------------------------------------------
helpers::wait_for_apt_lock() {
    local max_wait=120
    local waited=0
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        if (( waited >= max_wait )); then
            log::warn "dpkg lock held for >${max_wait}s; attempting to proceed anyway with lock timeout."
            break
        fi
        log::info "Waiting for system package manager to release dpkg lock (${waited}s)..."
        sleep 3
        waited=$((waited + 3))
    done
}

# -----------------------------------------------------------------------------
# helpers::apt_update_once
# Runs `apt-get update` at most once per script invocation (tracked via a
# marker file in /tmp) to avoid re-running it dozens of times across modules.
# -----------------------------------------------------------------------------
helpers::apt_update_once() {
    local marker="/tmp/.devbootstrap_apt_updated_$(date +%Y%m%d)"
    if [[ -f "$marker" ]]; then
        log::debug "apt-get update already run today, skipping"
        return 0
    fi
    log::info "Running apt-get update..."
    helpers::wait_for_apt_lock
    if helpers::with_apt_lock sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 update -y >>"${LOG_FILE}" 2>&1; then
        touch "$marker"
        log::debug "apt-get update completed"
    else
        log::error "apt-get update failed. See ${LOG_FILE}"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# helpers::apt_install <pkg1> [pkg2 ...]
# Installs one or more apt packages, skipping any that are already installed.
# Idempotent, non-interactive, logs output, lock-safe for parallel jobs.
# -----------------------------------------------------------------------------
helpers::apt_install() {
    local pkgs_to_install=()
    local pkg
    for pkg in "$@"; do
        if helpers::is_installed "$pkg"; then
            log::debug "Package '$pkg' already installed, skipping"
        else
            pkgs_to_install+=("$pkg")
        fi
    done

    if [[ ${#pkgs_to_install[@]} -eq 0 ]]; then
        log::debug "All requested packages already installed: $*"
        return 0
    fi

    helpers::apt_update_once || true
    helpers::wait_for_apt_lock
    log::info "Installing apt packages: ${pkgs_to_install[*]}"

    local install_cmd="sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 install -y --no-install-recommends"
    if helpers::with_apt_lock $install_cmd "${pkgs_to_install[@]}" >>"${LOG_FILE}" 2>&1; then
        log::success "Installed: ${pkgs_to_install[*]}"
        return 0
    fi

    log::warn "Batch install failed for: ${pkgs_to_install[*]}. Retrying one at a time."
    local failed=()
    local installed=()
    for pkg in "${pkgs_to_install[@]}"; do
        if helpers::is_installed "$pkg"; then
            continue
        fi
        helpers::wait_for_apt_lock
        if helpers::with_apt_lock $install_cmd "$pkg" >>"${LOG_FILE}" 2>&1; then
            log::success "Installed: ${pkg}"
            installed+=("$pkg")
        else
            log::warn "Package '${pkg}' could not be installed and will be skipped."
            failed+=("$pkg")
        fi
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        log::warn "Skipped unavailable packages: ${failed[*]}"
    fi

    # Return error if nothing was installed and everything failed
    if [[ ${#installed[@]} -eq 0 && ${#failed[@]} -gt 0 ]]; then
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# helpers::add_apt_repo <name> <repo-line> <keyring-url> <keyring-path>
# Adds a signed third-party apt repository idempotently.
#   name          - short identifier, used for the .list filename
#   repo-line     - the deb line, e.g.
#                    "deb [arch=$(dpkg --print-architecture) signed-by=<keyring>] https://... $(lsb_release -cs) stable"
#   keyring-url   - URL to download the GPG key from (or "" to skip)
#   keyring-path  - path to store the dearmored keyring, e.g. /etc/apt/keyrings/docker.gpg
# -----------------------------------------------------------------------------
helpers::add_apt_repo() {
    local name="$1" repo_line="$2" keyring_url="$3" keyring_path="$4"
    local list_file="/etc/apt/sources.list.d/${name}.list"

    sudo mkdir -p /etc/apt/keyrings

    if [[ -n "$keyring_url" ]]; then
        if [[ -f "$keyring_path" ]]; then
            log::debug "Keyring for '$name' already present at $keyring_path"
        else
            log::info "Fetching GPG key for repository '$name'"
            if curl -fsSL "$keyring_url" | sudo gpg --dearmor -o "$keyring_path" 2>>"${LOG_FILE}"; then
                sudo chmod a+r "$keyring_path"
                log::success "Keyring installed for '$name'"
            else
                log::error "Failed to fetch/install keyring for '$name'"
                return 1
            fi
        fi
    fi

    if [[ -f "$list_file" ]] && grep -qF "$repo_line" "$list_file" 2>/dev/null; then
        log::debug "Repository '$name' already configured"
        return 0
    fi

    echo "$repo_line" | sudo tee "$list_file" >/dev/null
    log::success "Repository '$name' added at $list_file"

    # Force a fresh apt update since sources changed.
    rm -f "/tmp/.devbootstrap_apt_updated_$(date +%Y%m%d)"
    helpers::apt_update_once
}

# -----------------------------------------------------------------------------
# helpers::download <url> <destination>
# Thin wrapper kept here for convenience; real implementation lives in
# downloads.sh to keep this file focused on package/repo management.
# -----------------------------------------------------------------------------
helpers::download() {
    downloads::fetch "$@"
}

# -----------------------------------------------------------------------------
# helpers::prompt <var_name> <question> <default>
# Prompts the user for input unless NON_INTERACTIVE=1, in which case the
# default is used automatically. Result is stored in the variable named by
# <var_name> (nameref).
# -----------------------------------------------------------------------------
helpers::prompt() {
    local -n __result_ref="$1"
    local question="$2"
    local default="${3:-}"

    if [[ "$NON_INTERACTIVE" == "1" ]]; then
        __result_ref="$default"
        log::debug "Non-interactive mode: '$question' -> default '$default'"
        return 0
    fi

    local answer
    if [[ -n "$default" ]]; then
        read -r -p "$(echo -e "${COLOR_MAGENTA}?${COLOR_RESET} ${question} [${default}]: ")" answer
        __result_ref="${answer:-$default}"
    else
        read -r -p "$(echo -e "${COLOR_MAGENTA}?${COLOR_RESET} ${question}: ")" answer
        __result_ref="${answer}"
    fi
}

# -----------------------------------------------------------------------------
# helpers::confirm <question> [default: y|n]
# Returns 0 (true) if the user confirms. In non-interactive mode, returns the
# default without prompting.
# -----------------------------------------------------------------------------
helpers::confirm() {
    local question="$1"
    local default="${2:-y}"
    local prompt_suffix="[y/N]"
    [[ "$default" == "y" ]] && prompt_suffix="[Y/n]"

    if [[ "$NON_INTERACTIVE" == "1" ]]; then
        [[ "$default" == "y" ]] && return 0 || return 1
    fi

    local answer
    read -r -p "$(echo -e "${COLOR_MAGENTA}?${COLOR_RESET} ${question} ${prompt_suffix}: ")" answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy] ]]
}

# -----------------------------------------------------------------------------
# helpers::retry <max_attempts> <sleep_seconds> <cmd...>
# Retries a command up to <max_attempts> times, useful for flaky network ops.
# -----------------------------------------------------------------------------
helpers::retry() {
    local max_attempts="$1"; shift
    local sleep_seconds="$1"; shift
    local attempt=1
    until "$@"; do
        if (( attempt >= max_attempts )); then
            log::error "Command failed after ${attempt} attempts: $*"
            return 1
        fi
        log::warn "Attempt ${attempt} failed, retrying in ${sleep_seconds}s: $*"
        sleep "$sleep_seconds"
        ((attempt++))
    done
}

# -----------------------------------------------------------------------------
# helpers::require_not_root
# Many steps (fnm, cargo, bun installers) must run as the invoking
# user, not root. install.sh already refuses to run as root entirely, but
# individual scripts call this too for defense in depth.
# -----------------------------------------------------------------------------
helpers::require_not_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        log::error "This step must not be run as root/sudo directly. Re-run install.sh as a normal user."
        return 1
    fi
}

# -----------------------------------------------------------------------------
# helpers::current_user_home
# Resolves the real user's home directory even when invoked via sudo.
# -----------------------------------------------------------------------------
helpers::current_user_home() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        getent passwd "${SUDO_USER}" | cut -d: -f6
    else
        echo "$HOME"
    fi
}

# -----------------------------------------------------------------------------
# helpers::line_in_file <file> <line>
# Appends <line> to <file> only if it isn't already present (idempotent
# shell-rc editing). Creates the file if missing.
# -----------------------------------------------------------------------------
helpers::line_in_file() {
    local file="$1" line="$2"
    touch "$file"
    if ! grep -qF -- "$line" "$file" 2>/dev/null; then
        echo "$line" >> "$file"
        log::debug "Added line to $file: $line"
    else
        log::debug "Line already present in $file"
    fi
}

# -----------------------------------------------------------------------------
# helpers::block_in_file <file> <marker> <block>
# Idempotently manages a marked block of shell config, e.g.:
#   # >>> devbootstrap:fnm >>>
#   ...content...
#   # <<< devbootstrap:fnm <<<
# Re-running with a different block updates it in place.
# -----------------------------------------------------------------------------
helpers::block_in_file() {
    local file="$1" marker="$2" block="$3"
    local start="# >>> devbootstrap:${marker} >>>"
    local end="# <<< devbootstrap:${marker} <<<"

    touch "$file"

    if grep -qF "$start" "$file" 2>/dev/null; then
        # Remove old block first (portable awk-based removal).
        awk -v s="$start" -v e="$end" '
            $0==s {skip=1}
            !skip {print}
            $0==e {skip=0}
        ' "$file" > "${file}.devbootstrap.tmp" && mv "${file}.devbootstrap.tmp" "$file"
    fi

    {
        echo "$start"
        echo "$block"
        echo "$end"
    } >> "$file"
    log::debug "Updated managed block '${marker}' in $file"
}

# -----------------------------------------------------------------------------
# helpers::detect_shell_rc
# Returns the path to the appropriate shell rc file for the current user,
# for both bash and zsh, so config can be written to whichever is active.
# -----------------------------------------------------------------------------
helpers::detect_shell_rc_files() {
    local home
    home="$(helpers::current_user_home)"
    local files=()
    [[ -f "${home}/.bashrc" ]] && files+=("${home}/.bashrc")
    [[ -f "${home}/.zshrc" ]] && files+=("${home}/.zshrc")
    # Ensure at least .bashrc exists so config always lands somewhere.
    if [[ ${#files[@]} -eq 0 ]]; then
        touch "${home}/.bashrc"
        files+=("${home}/.bashrc")
    fi
    printf '%s\n' "${files[@]}"
}

# -----------------------------------------------------------------------------
# helpers::mark_done / helpers::already_done
# Lightweight state tracking for expensive one-time steps that have no
# reliable "is it installed" check of their own (e.g. "database secured").
# State files live in logs/.state/<key>.
# -----------------------------------------------------------------------------
helpers::mark_done() {
    local key="$1"
    mkdir -p "${LOG_DIR}/.state"
    touch "${LOG_DIR}/.state/${key}"
}

helpers::already_done() {
    local key="$1"
    [[ -f "${LOG_DIR}/.state/${key}" ]]
}

# -----------------------------------------------------------------------------
# helpers::copy_to_clipboard <text>
# Attempts to copy text to the system clipboard via wl-copy or xclip.
# -----------------------------------------------------------------------------
helpers::copy_to_clipboard() {
    local text="$1"
    if helpers::command_exists wl-copy; then
        printf '%s' "$text" | wl-copy 2>/dev/null && return 0
    fi
    if helpers::command_exists xclip; then
        printf '%s' "$text" | xclip -selection clipboard 2>/dev/null && return 0
    fi
    return 1
}

export NON_INTERACTIVE
