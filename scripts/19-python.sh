#!/usr/bin/env bash
# =============================================================================
# scripts/19-python.sh
# -----------------------------------------------------------------------------
# Installs Python 3 and sets it up properly for development use:
#   - python3, pip, venv, dev headers via apt (official Ubuntu packages)
#   - a `python` -> `python3` shim, since Ubuntu ships no /usr/bin/python
#   - pipx for isolated, globally-available CLI tools (the correct approach
#     on Ubuntu 24.04+, which marks the system Python as "externally
#     managed" per PEP 668 and refuses plain `pip install --user`)
#   - a curated set of common Python CLI tools installed via pipx
#
# Tool list controlled via config/versions.conf: PIPX_TOOLS
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="19-python"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Python 3"

log::step "Core Python packages"
helpers::apt_install python3 python3-pip python3-venv python3-dev pipx

user_home="$(helpers::current_user_home)"

# ------------------------------------------------------------------------
# `python` shim: Ubuntu deliberately ships no /usr/bin/python to avoid
# ambiguity with Python 2. Most tools/scripts still assume `python` exists,
# so provide it via update-alternatives (system-wide, clean, reversible)
# rather than a hand-rolled symlink.
# ------------------------------------------------------------------------
log::step "python -> python3 shim"
if helpers::command_exists python; then
    log::info "'python' already resolves to: $(command -v python)"
else
    PYTHON3_BIN="$(command -v python3)"
    sudo update-alternatives --install /usr/bin/python python "$PYTHON3_BIN" 1 >>"${LOG_FILE}" 2>&1
    log::success "Configured 'python' -> ${PYTHON3_BIN} via update-alternatives"
fi

# ------------------------------------------------------------------------
# pipx: the officially recommended way (per PyPA and Ubuntu's own PEP 668
# guidance) to install and run Python CLI tools globally, each in its own
# isolated venv, without touching or fighting the system Python.
# ------------------------------------------------------------------------
log::step "pipx setup"
export PATH="${user_home}/.local/bin:${PATH}"

if helpers::command_exists pipx; then
    log::info "pipx already available: $(pipx --version)"
else
    log::error "pipx not found after apt install; something went wrong."
    exit 1
fi

log::info "Ensuring pipx's bin directory is on PATH..."
pipx ensurepath --force >>"${LOG_FILE}" 2>&1 || true
while IFS= read -r rc_file; do
    helpers::line_in_file "$rc_file" 'export PATH="$HOME/.local/bin:$PATH"'
done < <(helpers::detect_shell_rc_files)
log::success "pipx PATH configuration complete"

# ------------------------------------------------------------------------
# Common Python CLI tools, installed in isolated venvs via pipx.
# Override/extend the list via PIPX_TOOLS in config/versions.conf.
# ------------------------------------------------------------------------
log::step "Common Python CLI tools (via pipx)"
for tool in $PIPX_TOOLS; do
    if pipx list --short 2>/dev/null | grep -qE "^${tool} "; then
        log::debug "pipx package '${tool}' already installed"
    else
        log::info "Installing ${tool} via pipx..."
        pipx install "$tool" >>"${LOG_FILE}" 2>&1 \
            && log::success "${tool} installed" \
            || log::warn "Failed to install ${tool} via pipx (see ${LOG_FILE})"
    fi
done

log::success "Active python: $(python3 --version)"
log::success "Active pip: $(python3 -m pip --version)"

cat <<'EOF' | while IFS= read -r line; do log::info "$line"; done
Tip: this system's Python is "externally managed" (PEP 668). For project
dependencies, always use a virtual environment:
  python3 -m venv .venv && source .venv/bin/activate && pip install <package>
For global CLI tools, use pipx instead of pip:
  pipx install <tool>
EOF

log::success "Python step complete"
