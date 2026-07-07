#!/usr/bin/env bash
# =============================================================================
# scripts/03-git.sh
# -----------------------------------------------------------------------------
# Installs and configures Git: user identity, default branch, credential
# helper, and optional SSH commit signing.
#
# Values can be supplied non-interactively via .env:
#   GIT_USER_NAME, GIT_USER_EMAIL, GIT_DEFAULT_BRANCH, GIT_CREDENTIAL_HELPER,
#   GIT_ENABLE_SSH_SIGNING (true/false), GIT_SIGNING_KEY_PATH
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="03-git"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Git"

helpers::apt_install git

CURRENT_NAME="$(git config --global user.name 2>/dev/null || true)"
CURRENT_EMAIL="$(git config --global user.email 2>/dev/null || true)"

if [[ -n "$CURRENT_NAME" && -n "$CURRENT_EMAIL" ]]; then
    log::info "Git identity already configured: ${CURRENT_NAME} <${CURRENT_EMAIL}>"
else
    helpers::prompt GIT_NAME_INPUT "Git user.name" "${GIT_USER_NAME:-${CURRENT_NAME}}"
    helpers::prompt GIT_EMAIL_INPUT "Git user.email" "${GIT_USER_EMAIL:-${CURRENT_EMAIL}}"
    git config --global user.name "$GIT_NAME_INPUT"
    git config --global user.email "$GIT_EMAIL_INPUT"
    log::success "Configured git user.name/user.email"
fi

helpers::prompt GIT_BRANCH_INPUT "Default branch name" "${GIT_DEFAULT_BRANCH:-main}"
git config --global init.defaultBranch "$GIT_BRANCH_INPUT"

helpers::prompt GIT_CRED_HELPER_INPUT "Git credential helper (store/cache/manager/none)" "${GIT_CREDENTIAL_HELPER:-store}"
if [[ "$GIT_CRED_HELPER_INPUT" != "none" ]]; then
    git config --global credential.helper "$GIT_CRED_HELPER_INPUT"
    log::success "Set credential.helper=${GIT_CRED_HELPER_INPUT}"
fi

# Sane defaults that make life easier and are safe to set unconditionally.
git config --global pull.rebase false
git config --global core.editor "${EDITOR:-vim}"
git config --global color.ui auto
git config --global init.templateDir ""

# --- Optional SSH commit signing --------------------------------------------
GIT_ENABLE_SSH_SIGNING="${GIT_ENABLE_SSH_SIGNING:-}"
if [[ -z "$GIT_ENABLE_SSH_SIGNING" ]]; then
    if helpers::confirm "Enable SSH commit signing?" "n"; then
        GIT_ENABLE_SSH_SIGNING="true"
    else
        GIT_ENABLE_SSH_SIGNING="false"
    fi
fi

if [[ "$GIT_ENABLE_SSH_SIGNING" == "true" ]]; then
    user_home="$(helpers::current_user_home)"
    default_key="${GIT_SIGNING_KEY_PATH:-${user_home}/.ssh/id_ed25519.pub}"
    helpers::prompt SIGNING_KEY_INPUT "Path to SSH public key for signing" "$default_key"

    if [[ -f "$SIGNING_KEY_INPUT" ]]; then
        git config --global gpg.format ssh
        git config --global user.signingkey "$SIGNING_KEY_INPUT"
        git config --global commit.gpgsign true
        git config --global tag.gpgsign true
        log::success "SSH commit signing enabled with key: ${SIGNING_KEY_INPUT}"
    else
        log::warn "Signing key not found at ${SIGNING_KEY_INPUT}. Skipping SSH signing setup (run 04-ssh.sh first if needed)."
    fi
else
    log::info "Skipping SSH commit signing setup"
fi

log::success "Git configuration complete"
git config --global --list | while read -r line; do log::debug "git config: $line"; done
