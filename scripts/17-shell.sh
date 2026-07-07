#!/usr/bin/env bash
# =============================================================================
# scripts/17-shell.sh
# -----------------------------------------------------------------------------
# Configures shell quality-of-life improvements for both bash and zsh:
# useful aliases, completion, and prompt tweaks. All changes are written as
# idempotent managed blocks (see helpers::block_in_file) so re-running never
# duplicates content.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="17-shell"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Shell Configuration"

ALIASES_BLOCK='# --- General ---
alias ll="eza -la --group-directories-first"
alias ls="eza"
alias cat="bat --paging=never"
alias ..="cd .."
alias ...="cd ../.."
alias grep="grep --color=auto"
alias please="sudo"
alias c="clear"
alias h="history"

# --- Git ---
alias gs="git status"
alias ga="git add"
alias gc="git commit"
alias gp="git push"
alias gl="git log --oneline --graph --decorate"
alias gco="git checkout"
alias gb="git branch"
alias gd="git diff"

# --- Docker ---
alias dps="docker ps"
alias dc="docker compose"
alias dcu="docker compose up -d"
alias dcd="docker compose down"
alias dlog="docker logs -f"

# --- Node / package managers ---
alias ni="npm install"
alias nr="npm run"
alias pn="pnpm"
alias bx="bunx"

# --- Misc dev shortcuts ---
alias myip="curl -s ifconfig.me"
alias ports="sudo ss -tulpn"
alias reload="exec \$SHELL -l"'

while IFS= read -r rc_file; do
    helpers::block_in_file "$rc_file" "aliases" "$ALIASES_BLOCK"
done < <(helpers::detect_shell_rc_files)
log::success "Shell aliases configured"

# --------------------------- Bash completion --------------------------------
log::step "Bash completion"
helpers::apt_install bash-completion
BASH_COMPLETION_BLOCK='if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
    . /etc/bash_completion
fi'
user_home="$(helpers::current_user_home)"
if [[ -f "${user_home}/.bashrc" ]]; then
    helpers::block_in_file "${user_home}/.bashrc" "bash-completion" "$BASH_COMPLETION_BLOCK"
fi

# ----------------------------- Zsh completion -------------------------------
log::step "Zsh completion"
if helpers::command_exists zsh; then
    ZSH_COMPLETION_BLOCK='autoload -Uz compinit && compinit'
    if [[ -f "${user_home}/.zshrc" ]]; then
        helpers::block_in_file "${user_home}/.zshrc" "zsh-completion" "$ZSH_COMPLETION_BLOCK"
    fi
fi

# ----------------------- Tool-specific completions --------------------------
log::step "Tool completions"
if helpers::command_exists docker; then
    sudo mkdir -p /etc/bash_completion.d
    docker completion bash 2>/dev/null | sudo tee /etc/bash_completion.d/docker >/dev/null || true
fi

log::info "Detected default login shell: ${SHELL:-unknown}"
if [[ "${SHELL:-}" != */zsh ]] && helpers::command_exists zsh; then
    log::info "zsh is installed but not your default shell. Run 'chsh -s \$(which zsh)' to switch."
fi

log::success "Shell configuration step complete"
