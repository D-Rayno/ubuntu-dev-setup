#!/usr/bin/env bash
# =============================================================================
# scripts/20-workspace.sh
# -----------------------------------------------------------------------------
# Creates the personal workspace directory where development projects live
# (default: ~/Projects). Idempotent — safe to re-run, never overwrites
# existing content.
#
# Controlled via config/versions.conf: WORKSPACE_DIR
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="20-workspace"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Workspace Directory"

user_home="$(helpers::current_user_home)"
expanded_workspace_dir="${WORKSPACE_DIR/#\~/$user_home}"

if [[ -d "$expanded_workspace_dir" ]]; then
    log::info "Workspace directory already exists: ${expanded_workspace_dir}"
else
    mkdir -p "$expanded_workspace_dir"
    log::success "Created workspace directory: ${expanded_workspace_dir}"
fi

chown "$(id -un)":"$(id -gn)" "$expanded_workspace_dir" 2>/dev/null || true

# Convenience shell alias so `cd projects` (or your configured name) always
# jumps to the workspace, regardless of current directory.
WORKSPACE_ALIAS_NAME="$(basename "$expanded_workspace_dir" | tr '[:upper:]' '[:lower:]')"
WORKSPACE_BLOCK="alias ${WORKSPACE_ALIAS_NAME}=\"cd ${expanded_workspace_dir}\""
while IFS= read -r rc_file; do
    helpers::block_in_file "$rc_file" "workspace-dir" "$WORKSPACE_BLOCK"
done < <(helpers::detect_shell_rc_files)
log::success "Added shell alias '${WORKSPACE_ALIAS_NAME}' -> cd ${expanded_workspace_dir}"

log::success "Workspace directory step complete"
