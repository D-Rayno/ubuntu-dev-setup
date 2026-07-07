#!/usr/bin/env bash
# =============================================================================
# scripts/04-ssh.sh
# -----------------------------------------------------------------------------
# Sets up SSH for Git/GitHub use. Three scenarios, all handled automatically:
#
#   1. Keys already exist at ~/.ssh          -> just fix permissions & test
#   2. No keys, but you have an old backup   -> restore from it (optional,
#                                                only asked about if you say
#                                                you have one)
#   3. No keys and no backup                 -> generate a fresh ed25519
#                                                keypair and print the public
#                                                key so it can be added to
#                                                GitHub/GitLab
#
# Non-interactive overrides (.env):
#   SSH_BACKUP_DIR           path to a backup dir, e.g. ~/Backup/ssh
#   SSH_RESTORE_FROM_BACKUP  true|false — skips the "do you have a backup?"
#                            prompt when set
#   SSH_KEYGEN_EMAIL         email to embed in a freshly generated key's
#                            comment field (falls back to git user.email)
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="04-ssh"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "SSH Setup"

helpers::apt_install openssh-client openssh-server

user_home="$(helpers::current_user_home)"
ssh_dir="${user_home}/.ssh"
mkdir -p "$ssh_dir"

# -----------------------------------------------------------------------------
# ssh::has_existing_keys
# True if any private key already lives in ~/.ssh.
# -----------------------------------------------------------------------------
ssh::has_existing_keys() {
    [[ -n "$(find "$ssh_dir" -maxdepth 1 -type f -name 'id_*' ! -name '*.pub' 2>/dev/null)" ]]
}

if ssh::has_existing_keys; then
    log::info "SSH keys already present at ${ssh_dir}, skipping restore/generation"
else
    # --- Step 1: optionally restore from an old backup, only if the person
    # actually has one. Nothing is assumed and nothing is required. ---------
    want_restore="${SSH_RESTORE_FROM_BACKUP:-}"
    if [[ -z "$want_restore" ]]; then
        if helpers::confirm "Do you have an existing SSH key backup to restore?" "n"; then
            want_restore="true"
        else
            want_restore="false"
        fi
    fi

    if [[ "$want_restore" == "true" ]]; then
        helpers::prompt SSH_BACKUP_DIR_INPUT "Where is your SSH backup directory?" "${SSH_BACKUP_DIR:-~/Backup/ssh}"
        expanded_backup_dir="${SSH_BACKUP_DIR_INPUT/#\~/$user_home}"

        if [[ -d "$expanded_backup_dir" ]] && [[ -n "$(find "$expanded_backup_dir" -maxdepth 1 -name 'id_*' 2>/dev/null)" ]]; then
            log::info "Copying SSH keys from ${expanded_backup_dir} to ${ssh_dir}"
            cp -r "${expanded_backup_dir}/." "$ssh_dir/"
            log::success "SSH keys restored from backup"
        else
            log::warn "No usable SSH keys found in '${expanded_backup_dir}'. Falling back to generating a new key."
        fi
    else
        log::info "No backup selected; will generate a fresh key if needed."
    fi

    # --- Step 2: if we still have no keys (no backup, or backup was empty),
    # generate a brand new ed25519 keypair. ---------------------------------
    if ! ssh::has_existing_keys; then
        keygen_email="${SSH_KEYGEN_EMAIL:-}"
        if [[ -z "$keygen_email" ]]; then
            keygen_email="$(git config --global user.email 2>/dev/null || true)"
        fi
        if [[ -z "$keygen_email" ]]; then
            helpers::prompt keygen_email "Email to embed in the new SSH key's comment" "$(id -un)@$(hostname)"
        fi

        new_key_path="${ssh_dir}/id_ed25519"
        log::info "Generating a new ed25519 SSH key..."
        ssh-keygen -t ed25519 -C "$keygen_email" -f "$new_key_path" -N "" >>"${LOG_FILE}" 2>&1
        log::success "New SSH key generated at ${new_key_path}"

        echo ""
        echo -e "${COLOR_BOLD}${COLOR_CYAN}Your new public key (add this to GitHub/GitLab):${COLOR_RESET}"
        echo -e "${COLOR_YELLOW}$(cat "${new_key_path}.pub")${COLOR_RESET}"
        echo -e "GitHub: https://github.com/settings/ssh/new"
        echo ""
    fi
fi

# -----------------------------------------------------------------------------
# Permissions are always normalized, regardless of which path above was taken.
# -----------------------------------------------------------------------------
log::info "Restoring SSH directory permissions..."
chown -R "$(id -un)":"$(id -gn)" "$ssh_dir" 2>/dev/null || true
chmod 700 "$ssh_dir"
find "$ssh_dir" -maxdepth 1 -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} \;
find "$ssh_dir" -maxdepth 1 -type f -name "*.pub" -exec chmod 644 {} \;
[[ -f "${ssh_dir}/config" ]] && chmod 600 "${ssh_dir}/config"
[[ -f "${ssh_dir}/authorized_keys" ]] && chmod 600 "${ssh_dir}/authorized_keys"
log::success "SSH permissions normalized (700 dir, 600 private keys, 644 public keys)"

if helpers::command_exists ssh-agent && [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    log::debug "No ssh-agent detected in this shell session; add 'eval \$(ssh-agent -s)' to your shell rc if needed."
fi

log::info "Testing GitHub SSH connection..."
set +e
ssh_test_output="$(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -T git@github.com 2>&1)"
set -e
if echo "$ssh_test_output" | grep -q "successfully authenticated"; then
    log::success "GitHub SSH authentication succeeded"
elif ssh::has_existing_keys; then
    log::warn "GitHub SSH test did not confirm authentication (this is expected if the key above isn't added to GitHub yet)."
    log::warn "$ssh_test_output"
fi

# Point Git at SSH instead of HTTPS for github.com.
git config --global url."git@github.com:".insteadOf "https://github.com/"
log::success "Configured Git to use SSH for github.com URLs"

log::success "SSH setup step complete"
