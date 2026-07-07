#!/usr/bin/env bash
# =============================================================================
# lib/colors.sh
# -----------------------------------------------------------------------------
# ANSI color and formatting definitions used across all installer modules.
# This file only defines variables/functions; it has no side effects and is
# safe to `source` multiple times.
# =============================================================================

# Guard against double-sourcing redefinition noise (harmless but tidy).
if [[ -n "${__DEVBOOTSTRAP_COLORS_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
__DEVBOOTSTRAP_COLORS_LOADED=1

# Only emit color codes when connected to a real terminal. When output is
# redirected to a log file we want plain text, so scripts should call
# colors::init after they know whether they're writing to a TTY.
if [[ -t 1 ]]; then
    COLOR_RESET='\033[0m'
    COLOR_BOLD='\033[1m'
    COLOR_DIM='\033[2m'
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_MAGENTA='\033[0;35m'
    COLOR_CYAN='\033[0;36m'
    COLOR_WHITE='\033[0;37m'
else
    COLOR_RESET=''
    COLOR_BOLD=''
    COLOR_DIM=''
    COLOR_RED=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_MAGENTA=''
    COLOR_CYAN=''
    COLOR_WHITE=''
fi

export COLOR_RESET COLOR_BOLD COLOR_DIM COLOR_RED COLOR_GREEN COLOR_YELLOW \
       COLOR_BLUE COLOR_MAGENTA COLOR_CYAN COLOR_WHITE
