#!/usr/bin/env bash
# =============================================================================
# scripts/21-ai-agents.sh
# -----------------------------------------------------------------------------
# Installs and configures the AI Agent toolchain:
#   1. Antigravity IDE (tar.gz -> /opt/Antigravity-IDE with custom dark icon)
#   2. Antigravity 2.0 (tar.gz -> /opt/Antigravity with custom light icon)
#   3. Claude Code (@anthropic-ai/claude-code via npm)
#   4. OpenAI Codex CLI (@openai/codex via npm)
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="21-ai-agents"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "AI Agents (Antigravity IDE & 2.0, Claude Code, Codex)"

user_home="$(helpers::current_user_home)"
user_downloads="${user_home}/Downloads"

# -----------------------------------------------------------------------------
# 1. Custom Icon Generation
# -----------------------------------------------------------------------------
log::step "Generating Custom Antigravity Icons"
icon_gen_script="${DEVBOOTSTRAP_ROOT}/lib/assets/generate_icons.py"
icons_dir="${DEVBOOTSTRAP_ROOT}/lib/assets"

if [[ -f "$icon_gen_script" ]]; then
    python3 "$icon_gen_script" "$icons_dir/antigravity.png" "$icons_dir" >>"${LOG_FILE}" 2>&1 || log::warn "Icon generation reported issues"
fi

user_icons_dir="${user_home}/.local/share/icons/hicolor/512x512/apps"
mkdir -p "$user_icons_dir"
if [[ -f "$icons_dir/antigravity-ide.png" ]]; then
    cp "$icons_dir/antigravity-ide.png" "$user_icons_dir/antigravity-ide.png"
    if sudo -n true 2>/dev/null; then
        sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
        sudo cp "$icons_dir/antigravity-ide.png" /usr/share/icons/hicolor/512x512/apps/antigravity-ide.png 2>/dev/null || true
    fi
    log::success "Antigravity IDE dark icon installed"
fi
if [[ -f "$icons_dir/antigravity-2.0.png" ]]; then
    cp "$icons_dir/antigravity-2.0.png" "$user_icons_dir/antigravity.png"
    if sudo -n true 2>/dev/null; then
        sudo mkdir -p /usr/share/icons/hicolor/512x512/apps
        sudo cp "$icons_dir/antigravity-2.0.png" /usr/share/icons/hicolor/512x512/apps/antigravity.png 2>/dev/null || true
    fi
    log::success "Antigravity 2.0 light icon installed"
fi

# -----------------------------------------------------------------------------
# 2. Antigravity IDE Installation
# -----------------------------------------------------------------------------
log::step "Antigravity IDE"
ide_tarball=""
for candidate in "${user_downloads}/Antigravity IDE.tar.gz" "${user_downloads}/Antigravity*IDE*.tar.gz"; do
    if [[ -f "$candidate" ]]; then
        ide_tarball="$candidate"
        break
    fi
done

if [[ -n "$ide_tarball" ]]; then
    log::info "Found Antigravity IDE archive: $(basename "$ide_tarball")"
    sudo mkdir -p /opt/Antigravity-IDE
    log::info "Extracting Antigravity IDE to /opt/Antigravity-IDE..."
    sudo tar -xzf "$ide_tarball" -C /opt/Antigravity-IDE --strip-components=1 >>"${LOG_FILE}" 2>&1

    # Fix Electron SUID sandbox permissions
    if [[ -f /opt/Antigravity-IDE/chrome-sandbox ]]; then
        sudo chown root:root /opt/Antigravity-IDE/chrome-sandbox
        sudo chmod 4755 /opt/Antigravity-IDE/chrome-sandbox
    fi

    # Copy dark icon
    if [[ -f "$icons_dir/antigravity-ide.png" ]]; then
        sudo mkdir -p /opt/Antigravity-IDE/resources
        sudo cp "$icons_dir/antigravity-ide.png" /opt/Antigravity-IDE/resources/icon.png
    fi

    # Symlink to bin
    mkdir -p "${user_home}/.local/bin"
    if [[ -f /opt/Antigravity-IDE/antigravity-ide ]]; then
        ln -sf /opt/Antigravity-IDE/antigravity-ide "${user_home}/.local/bin/antigravity-ide"
        if sudo -n true 2>/dev/null; then
            sudo ln -sf /opt/Antigravity-IDE/antigravity-ide /usr/local/bin/antigravity-ide 2>/dev/null || true
        fi
    fi

    # Create desktop launcher
    mkdir -p "${user_home}/.local/share/applications"
    cat <<EOF > "${user_home}/.local/share/applications/antigravity-ide.desktop"
[Desktop Entry]
Name=Antigravity IDE
Comment=AI-First Integrated Development Environment
GenericName=Text Editor
Exec=/opt/Antigravity-IDE/antigravity-ide %F
Icon=${user_icons_dir}/antigravity-ide.png
Type=Application
StartupNotify=true
StartupWMClass=Antigravity IDE
Categories=Development;IDE;TextEditor;
MimeType=text/plain;inode/directory;
EOF
    if sudo -n true 2>/dev/null; then
        sudo cp "${user_home}/.local/share/applications/antigravity-ide.desktop" /usr/share/applications/antigravity-ide.desktop 2>/dev/null || true
    fi
    log::success "Antigravity IDE installed and desktop launcher created"
elif helpers::command_exists antigravity-ide || [[ -d /opt/Antigravity-IDE ]]; then
    log::info "Antigravity IDE is already installed"
else
    log::warn "Antigravity IDE archive ('Antigravity IDE.tar.gz') not found in ${user_downloads}."
fi

# -----------------------------------------------------------------------------
# 3. Antigravity 2.0 Installation
# -----------------------------------------------------------------------------
log::step "Antigravity 2.0"
app_tarball=""
for candidate in "${user_downloads}/Antigravity.tar.gz" "${user_downloads}/Antigravity-*.tar.gz"; do
    if [[ -f "$candidate" && "$candidate" != *"IDE"* ]]; then
        app_tarball="$candidate"
        break
    fi
done

if [[ -n "$app_tarball" ]]; then
    log::info "Found Antigravity 2.0 archive: $(basename "$app_tarball")"
    sudo mkdir -p /opt/Antigravity
    log::info "Extracting Antigravity 2.0 to /opt/Antigravity..."
    sudo tar -xzf "$app_tarball" -C /opt/Antigravity --strip-components=1 >>"${LOG_FILE}" 2>&1

    # Fix Electron SUID sandbox permissions
    if [[ -f /opt/Antigravity/chrome-sandbox ]]; then
        sudo chown root:root /opt/Antigravity/chrome-sandbox
        sudo chmod 4755 /opt/Antigravity/chrome-sandbox
    fi

    # Copy light icon
    if [[ -f "$icons_dir/antigravity-2.0.png" ]]; then
        sudo mkdir -p /opt/Antigravity/resources
        sudo cp "$icons_dir/antigravity-2.0.png" /opt/Antigravity/resources/icon.png
    fi

    # Symlink to bin
    mkdir -p "${user_home}/.local/bin"
    if [[ -f /opt/Antigravity/antigravity ]]; then
        ln -sf /opt/Antigravity/antigravity "${user_home}/.local/bin/antigravity"
        if sudo -n true 2>/dev/null; then
            sudo ln -sf /opt/Antigravity/antigravity /usr/local/bin/antigravity 2>/dev/null || true
        fi
    fi

    # Create desktop launcher
    mkdir -p "${user_home}/.local/share/applications"
    cat <<EOF > "${user_home}/.local/share/applications/antigravity.desktop"
[Desktop Entry]
Name=Antigravity 2.0
Comment=Antigravity Desktop Agent Orchestrator
GenericName=AI Development Assistant
Exec=/opt/Antigravity/antigravity %U
Icon=${user_icons_dir}/antigravity.png
Type=Application
StartupNotify=true
StartupWMClass=Antigravity
Categories=Development;
MimeType=x-scheme-handler/antigravity;
EOF
    if sudo -n true 2>/dev/null; then
        sudo cp "${user_home}/.local/share/applications/antigravity.desktop" /usr/share/applications/antigravity.desktop 2>/dev/null || true
    fi
    log::success "Antigravity 2.0 installed and desktop launcher created"
elif helpers::command_exists antigravity || [[ -d /opt/Antigravity ]]; then
    log::info "Antigravity 2.0 is already installed"
else
    log::warn "Antigravity 2.0 archive ('Antigravity.tar.gz') not found in ${user_downloads}."
fi

# -----------------------------------------------------------------------------
# 4. CLI AI Agents (Claude Code & OpenAI Codex)
# -----------------------------------------------------------------------------
log::step "CLI AI Agents (Claude Code & OpenAI Codex)"

# Ensure fnm-managed node/npm are loaded in this subshell
export FNM_DIR="${FNM_DIR:-${user_home}/.local/share/fnm}"
export PATH="${FNM_DIR}:${user_home}/.local/bin:${PATH}"
if helpers::command_exists fnm; then
    eval "$(fnm env --shell bash 2>/dev/null || true)"
fi

if helpers::command_exists npm; then
    # Claude Code
    if helpers::command_exists claude && claude --version >/dev/null 2>&1; then
        log::info "Claude Code already installed: $(claude --version 2>/dev/null || echo 'ready')"
    else
        log::info "Installing Claude Code (@anthropic-ai/claude-code)..."
        npm install -g @anthropic-ai/claude-code >>"${LOG_FILE}" 2>&1 || true
        # Ensure native binary postinstall is executed
        global_root="$(npm root -g 2>/dev/null || true)"
        if [[ -f "${global_root}/@anthropic-ai/claude-code/install.cjs" ]]; then
            node "${global_root}/@anthropic-ai/claude-code/install.cjs" >>"${LOG_FILE}" 2>&1 || true
        fi
        if helpers::command_exists claude; then
            log::success "Claude Code installed: $(claude --version 2>/dev/null || echo 'ready')"
        else
            log::warn "Claude Code installation reported an issue"
        fi
    fi

    # OpenAI Codex CLI
    if helpers::command_exists codex; then
        log::info "OpenAI Codex CLI already installed: $(codex --version 2>/dev/null || echo 'ready')"
    else
        log::info "Installing OpenAI Codex CLI (@openai/codex)..."
        npm install -g @openai/codex >>"${LOG_FILE}" 2>&1 \
            && log::success "OpenAI Codex CLI installed: $(codex --version 2>/dev/null || echo 'ready')" \
            || log::warn "OpenAI Codex CLI installation reported an issue"
    fi
else
    log::warn "Node.js / npm not available in PATH. Skipping Claude Code and Codex CLI install (ensure 05-fnm-node.sh runs first)."
fi

log::success "AI Agents step complete"
