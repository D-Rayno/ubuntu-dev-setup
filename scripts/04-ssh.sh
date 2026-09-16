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

utils::print_banner "SSH Key Setup (GitHub & GitLab)"

helpers::apt_install openssh-client openssh-server

user_home="$(helpers::current_user_home)"
ssh_dir="${user_home}/.ssh"
mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"

primary_private_key="${ssh_dir}/id_ed25519"
primary_public_key="${ssh_dir}/id_ed25519.pub"

# Find any existing private key
existing_keys=()
while IFS= read -r -d $'\0' key; do
    existing_keys+=("$key")
done < <(find "$ssh_dir" -maxdepth 1 -type f \( -name "id_*" ! -name "*.pub" \) -print0 2>/dev/null)

key_choice="generate"
if [[ ${#existing_keys[@]} -gt 0 ]]; then
    log::info "Found existing SSH key(s):"
    for k in "${existing_keys[@]}"; do
        echo "  - $(basename "$k")"
    done

    if [[ "$NON_INTERACTIVE" == "1" ]]; then
        key_choice="keep"
    else
        echo ""
        helpers::prompt key_choice "Do you want to [k]eep existing key, [i]mport an old key, or [g]enerate a new key?" "k"
        case "${key_choice,,}" in
            k|keep) key_choice="keep" ;;
            i|import) key_choice="import" ;;
            g|gen|generate) key_choice="generate" ;;
            *) key_choice="keep" ;;
        esac
    fi
fi

if [[ "$key_choice" == "import" || (${#existing_keys[@]} -eq 0 && "$key_choice" != "keep") ]]; then
    imported=0
    if [[ "$NON_INTERACTIVE" != "1" ]]; then
        echo ""
        echo -e "${COLOR_BOLD}${COLOR_CYAN}SSH Key Import:${COLOR_RESET}"
        echo "You can provide an existing private key (file path or paste content)."
        echo "Leave blank and press Enter to generate a new ed25519 keypair automatically."
        helpers::prompt key_input "Enter path to old private key (or leave blank to generate new)" ""

        if [[ -n "$key_input" ]]; then
            expanded_key="${key_input/#\~/$user_home}"
            if [[ -f "$expanded_key" ]]; then
                log::info "Importing private key from ${expanded_key}..."
                cp "$expanded_key" "$primary_private_key"
                chmod 600 "$primary_private_key"
                # Derive public key from private key
                if ssh-keygen -y -f "$primary_private_key" > "$primary_public_key" 2>/dev/null; then
                    chmod 644 "$primary_public_key"
                    log::success "Imported private key and derived public key successfully"
                    imported=1
                else
                    log::warn "Failed to derive public key from ${expanded_key}. Key might be invalid or encrypted."
                fi
            else
                log::warn "File '${expanded_key}' does not exist."
            fi
        fi
    fi

    # If not imported, generate a fresh key
    if [[ "$imported" -eq 0 && "$key_choice" != "keep" ]]; then
        keygen_email="${SSH_KEYGEN_EMAIL:-}"
        if [[ -z "$keygen_email" ]]; then
            keygen_email="$(git config --global user.email 2>/dev/null || true)"
        fi
        if [[ -z "$keygen_email" && "$NON_INTERACTIVE" != "1" ]]; then
            helpers::prompt keygen_email "Email comment for new SSH key" "$(id -un)@$(hostname)"
        fi
        keygen_email="${keygen_email:-$(id -un)@$(hostname)}"

        log::info "Generating fresh ed25519 SSH keypair..."
        rm -f "$primary_private_key" "$primary_public_key"
        ssh-keygen -t ed25519 -C "$keygen_email" -f "$primary_private_key" -N "" >>"${LOG_FILE}" 2>&1
        log::success "Generated new ed25519 key at ${primary_private_key}"
    fi
fi

# Locate the active public key
active_pub=""
if [[ -f "$primary_public_key" ]]; then
    active_pub="$primary_public_key"
else
    first_pub="$(find "$ssh_dir" -maxdepth 1 -name "*.pub" | head -n1)"
    [[ -n "$first_pub" ]] && active_pub="$first_pub"
fi

# Permissions normalization
log::info "Normalizing SSH directory permissions..."
chown -R "$(id -un)":"$(id -gn)" "$ssh_dir" 2>/dev/null || true
chmod 700 "$ssh_dir"
find "$ssh_dir" -maxdepth 1 -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} \;
find "$ssh_dir" -maxdepth 1 -type f -name "*.pub" -exec chmod 644 {} \;
[[ -f "${ssh_dir}/config" ]] && chmod 600 "${ssh_dir}/config"
[[ -f "${ssh_dir}/authorized_keys" ]] && chmod 600 "${ssh_dir}/authorized_keys"
log::success "SSH permissions normalized (700 dir, 600 private keys, 644 public keys)"

if [[ -n "$active_pub" && -f "$active_pub" ]]; then
    pub_content="$(cat "$active_pub")"
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_GREEN}════════════════════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_GREEN} Your SSH Public Key (${active_pub}):${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}${pub_content}${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_GREEN}════════════════════════════════════════════════════════${COLOR_RESET}"

    if helpers::copy_to_clipboard "$pub_content"; then
        log::success "Copied public key to clipboard!"
    fi

    echo ""
    echo -e "${COLOR_BOLD}Add this key to your Git providers:${COLOR_RESET}"
    echo -e "  • ${COLOR_CYAN}GitHub:${COLOR_RESET} https://github.com/settings/ssh/new"
    echo -e "  • ${COLOR_CYAN}GitLab:${COLOR_RESET} https://gitlab.com/-/user_settings/ssh_keys"
    echo ""

    if [[ "$NON_INTERACTIVE" != "1" ]]; then
        helpers::prompt proceed_test "Set the key in your provider(s) then press [Enter] to test (or type 'skip')" ""
    else
        proceed_test=""
    fi

    if [[ "${proceed_test,,}" != "skip" ]]; then
        # Test GitHub
        log::info "Testing connection to GitHub (git@github.com)..."
        set +e
        github_output="$(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -T git@github.com 2>&1)"
        github_exit=$?
        set -e
        if echo "$github_output" | grep -iq "successfully authenticated"; then
            log::success "GitHub SSH: Authenticated successfully! ($(echo "$github_output" | grep -i "Hi " | head -n1))"
        else
            log::warn "GitHub SSH: Not authenticated yet. Response: $(echo "$github_output" | head -n1)"
        fi

        # Test GitLab
        log::info "Testing connection to GitLab (git@gitlab.com)..."
        set +e
        gitlab_output="$(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -T git@gitlab.com 2>&1)"
        gitlab_exit=$?
        set -e
        if echo "$gitlab_output" | grep -iq "Welcome to GitLab"; then
            log::success "GitLab SSH: Authenticated successfully! ($(echo "$gitlab_output" | grep -i "Welcome" | head -n1))"
        else
            log::warn "GitLab SSH: Not authenticated yet. Response: $(echo "$gitlab_output" | head -n1)"
        fi
    fi
fi

# Configure Git to use SSH URLs for github
git config --global url."git@github.com:".insteadOf "https://github.com/"
log::success "Configured Git to use SSH for github.com URLs"

log::success "SSH setup complete"
