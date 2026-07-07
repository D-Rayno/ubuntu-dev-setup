#!/usr/bin/env bash
# =============================================================================
# scripts/10-java.sh
# -----------------------------------------------------------------------------
# Installs OpenJDK from Ubuntu's official repositories and manages multiple
# side-by-side versions with `update-alternatives` — the same pattern used
# for PHP in scripts/07-php.sh.
#
# This intentionally does NOT use SDKMAN. SDKMAN's `sdk` command is a shell
# function full of interactive confirmation prompts ("Do you want java to be
# set as default?") and non-zero internal returns used for control flow, both
# of which fight badly with `set -Eeuo pipefail` and non-interactive runs —
# that combination was the source of the install failures this module used
# to have. apt + update-alternatives has none of that: it's idempotent,
# scriptable, and it's exactly how Ubuntu expects multiple JDKs to coexist.
#
# Versions installed are controlled via config/versions.conf:
#   JAVA_VERSIONS         space-separated list, e.g. "17" or "17 21"
#   JAVA_DEFAULT_VERSION  which one `java`/`javac` should point to by default
#
# Only Java 17 is installed by default. Add more versions any time by editing
# JAVA_VERSIONS and re-running: ./install.sh --only 10
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
CURRENT_MODULE="10-java"
trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

utils::print_banner "Java (OpenJDK)"

for version in $JAVA_VERSIONS; do
    log::step "Installing OpenJDK ${version}"
    helpers::apt_install "openjdk-${version}-jdk"
done

# -----------------------------------------------------------------------------
# Register every installed version with update-alternatives so `java`,
# `javac`, and friends can be switched cleanly, then set the configured
# default. Priority = version number so higher versions win ties if
# update-alternatives is ever asked to pick automatically.
# -----------------------------------------------------------------------------
log::step "Configuring update-alternatives"

JAVA_TOOLS="java javac jar jshell javadoc"

for version in $JAVA_VERSIONS; do
    jvm_dir="$(compgen -G "/usr/lib/jvm/java-${version}-openjdk-*" | head -n1 || true)"

    if [[ -z "$jvm_dir" || ! -d "$jvm_dir" ]]; then
        log::warn "Could not locate JVM directory for Java ${version}; skipping update-alternatives registration."
        continue
    fi

    for tool in $JAVA_TOOLS; do
        tool_bin="${jvm_dir}/bin/${tool}"
        if [[ -x "$tool_bin" ]]; then
            sudo update-alternatives --install "/usr/bin/${tool}" "$tool" "$tool_bin" "$version" >>"${LOG_FILE}" 2>&1 || true
        fi
    done
    log::success "Registered Java ${version} (${jvm_dir}) with update-alternatives"
done

log::info "Setting Java ${JAVA_DEFAULT_VERSION} as the active default..."
default_jvm_dir="$(compgen -G "/usr/lib/jvm/java-${JAVA_DEFAULT_VERSION}-openjdk-*" | head -n1 || true)"
if [[ -n "$default_jvm_dir" ]]; then
    for tool in $JAVA_TOOLS; do
        tool_bin="${default_jvm_dir}/bin/${tool}"
        [[ -x "$tool_bin" ]] && sudo update-alternatives --set "$tool" "$tool_bin" >>"${LOG_FILE}" 2>&1 || true
    done
    log::success "Default Java set to ${JAVA_DEFAULT_VERSION}"
else
    log::warn "Could not set default Java version automatically; run 'sudo update-alternatives --config java' manually."
fi

# JAVA_HOME: set idempotently in shell rc for tools (Maven, Gradle, IDEs)
# that expect it, always pointing at the configured default version.
if [[ -n "$default_jvm_dir" ]]; then
    JAVA_HOME_BLOCK="export JAVA_HOME=\"${default_jvm_dir}\"
export PATH=\"\$JAVA_HOME/bin:\$PATH\""
    while IFS= read -r rc_file; do
        helpers::block_in_file "$rc_file" "java-home" "$JAVA_HOME_BLOCK"
    done < <(helpers::detect_shell_rc_files)
    log::success "JAVA_HOME configured: ${default_jvm_dir}"
fi

log::success "Active java: $(java -version 2>&1 | head -n1)"

cat <<'EOF' | while IFS= read -r line; do log::info "$line"; done
Tip: switch the active Java version any time with:
  sudo update-alternatives --config java
  sudo update-alternatives --config javac
Add more versions by editing JAVA_VERSIONS in config/versions.conf, then:
  ./install.sh --only 10
EOF

log::success "Java step complete"
