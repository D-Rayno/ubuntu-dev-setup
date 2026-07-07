# ubuntu-dev-bootstrap

A modular, idempotent, resumable installer that turns a fresh **Ubuntu**
machine into a complete, opinionated development environment — automatically.
Built for 24.04 LTS, and designed to keep working on newer Ubuntu releases
(24.10, 25.04, 25.10, 26.04, …) as they come out.

```bash
git clone <repo>
cd ubuntu-dev-bootstrap
chmod +x install.sh
./install.sh
```

That's it. Run it again any time — every module checks what's already installed
and skips it, so re-running is always safe. If it ever crashes partway
through (lost network, closed terminal, etc.), just run `./install.sh` again:
completed modules are skipped automatically and it picks up exactly where it
left off.

---

## Table of Contents

- [What gets installed](#what-gets-installed)
- [Installation](#installation)
- [Configuration](#configuration)
- [Command-line options](#command-line-options)
- [Project structure](#project-structure)
- [Updating](#updating)
- [Adding a new module](#adding-a-new-module)
- [Logging](#logging)
- [Troubleshooting](#troubleshooting)
- [Supported Ubuntu versions](#supported-ubuntu-versions)
- [License](#license)

---

## What gets installed

| Module | Tool(s) |
|---|---|
| 01 | System update (`apt-get update && upgrade`) |
| 02 | Base CLI packages: build-essential, curl, git, ripgrep, fzf, bat, eza, htop, tmux, zsh, jq, and more |
| 03 | Git (identity, default branch, credential helper, optional SSH commit signing) |
| 04 | SSH (restores keys from a backup **only if you have one**; otherwise generates a fresh ed25519 key; fixes permissions; tests GitHub connectivity) |
| 05 | Node.js via **fnm**, npm, Corepack, **pnpm** |
| 06 | **Bun** |
| 07 | PHP 8.2 / 8.3 / 8.4 (official `packages.sury.org/php` repository) with common extensions |
| 08 | **Composer** (signature-verified install) + Laravel installer |
| 09 | **Docker Engine**, Compose plugin, Buildx |
| 10 | **Java** — OpenJDK via apt + `update-alternatives` (multi-version capable; only 17 installed by default) |
| 11 | **MySQL** + **PostgreSQL** (services enabled, dev user/db created) |
| 12 | **Redis** |
| 13 | **Rust** via rustup + common cargo utilities |
| 14 | Framework CLIs: TypeScript, ESLint, Prettier, Vite, Turbo, Nx, Vue CLI, Angular CLI, Next.js, Nuxt, NestJS CLI, Tauri CLI, Expo/React Native CLIs, Laravel Installer |
| 15 | Desktop apps: **Chrome, VS Code, Discord, Antigravity IDE, TablePlus** (official repos/.deb) + **snap**: Android Studio, Postman, Telegram, WhatsApp (Whatsie, with automatic fallback candidates) |
| 16 | NVIDIA driver (auto-detected) + optional CUDA toolkit |
| 17 | Shell aliases + bash/zsh completion |
| 18 | Final validation + summary report |
| 19 | Python 3 (pip, venv, dev headers, `python` shim, pipx-managed global CLI tools) |
| 20 | **Workspace directory** (`~/Projects` by default) + a shell alias to jump to it |

Every apt-based install prefers the **official** vendor repository. Unofficial
PPAs are never used — PHP uses the official `packages.sury.org/php` repo
(deb822 format + dedicated keyring package, exactly as documented at
php.net/downloads), and Java uses Ubuntu's own OpenJDK packages. Snap is used
**only** for Android Studio, Postman, Telegram, and WhatsApp, per project
policy.

---

## Installation

### Requirements

- Ubuntu 24.04 LTS or newer (24.10, 25.04, 25.10, 26.04, …) — fresh install
  recommended, but safe on an existing system. Running on a non-Ubuntu system
  prints a warning but is not blocked.
- A non-root user with `sudo` privileges
- An internet connection

### Quick start

```bash
git clone <repo-url> ubuntu-dev-bootstrap
cd ubuntu-dev-bootstrap
chmod +x install.sh
./install.sh
```

The script will:
1. Detect your Ubuntu release (warns, but doesn't block, on anything else).
2. Ask for your `sudo` password once up front (cached for the run).
3. Prompt for a few values it can't infer (Git identity; whether you have an
   old SSH key backup to restore) — unless you've pre-filled `.env` and pass
   `--non-interactive`.
4. Run all 20 modules in order, logging everything to `logs/install.log`.
5. Print a validation summary at the end.

### Fully non-interactive install

```bash
cp .env.example .env
nano .env                     # fill in your Git identity, SSH backup dir, etc.
./install.sh --non-interactive
```

---

## Configuration

Three files under `config/` control *what* gets installed and *which versions*,
without touching any script logic:

| File | Purpose |
|---|---|
| `config/packages.conf` | The `BASE_PACKAGES` array installed by module 02 |
| `config/versions.conf` | Node/PHP/Java versions, DB credentials, Rust toolchain, cargo utils, pipx tools, workspace directory, NVIDIA/CUDA toggles |
| `config/apps.conf` | Snap app list (with fallback candidates) and official-repo app list for module 15 |

`.env` (copied from `.env.example`) holds personal/secret values that
shouldn't live in tracked config: Git name/email, SSH backup directory,
and behavior flags (`VERBOSE`, `NON_INTERACTIVE`).

Example — pinning a specific Node LTS, adding a PHP version, and adding Java 21
alongside the default Java 17:

```bash
# config/versions.conf
NODE_LTS_ALIAS="20.17.0"
PHP_VERSIONS="8.2 8.3 8.4 8.1"
JAVA_VERSIONS="17 21"
JAVA_DEFAULT_VERSION="17"
```

Then just re-run `./install.sh --only 05,07,10` to apply the change without
touching anything else.

---

## Command-line options

```
./install.sh                     Run every module, auto-skipping any already
                                  completed successfully in a previous run
./install.sh --only 05,06,09     Force-run only the specified modules, even
                                  if they were already completed
./install.sh --skip 16           Run everything except the given modules
./install.sh --from 09           Resume starting at a given module
./install.sh --force             Ignore completion state; redo everything
./install.sh --reset             Clear all completion state and exit
./install.sh --list              List all available modules and exit
./install.sh --verbose           Enable debug-level logging
./install.sh --non-interactive   Never prompt; use defaults / .env values
./install.sh --dry-run           Print the module plan without running it
./install.sh -h | --help         Show help text
```

### Automatic resume after a crash or lost connection

Every module that finishes successfully is recorded in `logs/.state/`. If the
installer crashes or loses network partway through — say, PHP 8.4 fails to
download — you don't need to figure out where it stopped. Just run it again:

```bash
./install.sh
```

Modules 01–06 (already completed) are skipped instantly, and it picks back up
at the PHP module automatically. This applies to *any* module, not just PHP.

If you want to force a specific module to redo its work even though it's
already marked complete (e.g. to pick up a newer version), name it explicitly:

```bash
./install.sh --only 07
```

Explicitly-named modules (via `--only`) always run, regardless of past
completion. To force *everything* to redo regardless of past state, use
`--force`. To wipe the slate clean entirely (e.g. before a fresh test run):

```bash
./install.sh --reset      # clears all "completed" markers
./install.sh              # runs every module from scratch
```

Examples:

```bash
# Just re-run after a crash — this is usually all you need
./install.sh

# Only reconfigure databases and Redis, even if already done
./install.sh --only 11,12

# Manually resume starting at a given module (rarely needed — auto-resume
# usually handles this already)
./install.sh --from 09

# See what would run without doing anything
./install.sh --dry-run
```

---

## Project structure

```
ubuntu-dev-bootstrap/
├── install.sh                 # Orchestrator: parses args, runs modules in order
├── README.md
├── .env.example                # Copy to .env for non-interactive values
├── config/
│   ├── packages.conf           # Base apt package list
│   ├── versions.conf           # Tool versions & DB credentials
│   └── apps.conf                # Desktop app manifest
├── scripts/
│   ├── 00-utils.sh              # Bootstrap: sourced first by every module
│   ├── 01-system-update.sh
│   ├── 02-base-packages.sh
│   ├── 03-git.sh
│   ├── 04-ssh.sh
│   ├── 05-fnm-node.sh
│   ├── 06-bun.sh
│   ├── 07-php.sh
│   ├── 08-composer.sh
│   ├── 09-docker.sh
│   ├── 10-java.sh
│   ├── 11-databases.sh
│   ├── 12-redis.sh
│   ├── 13-rust.sh
│   ├── 14-frameworks.sh
│   ├── 15-desktop-apps.sh
│   ├── 16-drivers.sh
│   ├── 17-shell.sh
│   ├── 18-finalize.sh
│   ├── 19-python.sh
│   └── 20-workspace.sh
├── lib/
│   ├── colors.sh                # ANSI color definitions
│   ├── logger.sh                # log::info / warn / error / success / debug / step
│   ├── helpers.sh                # apt install/repo helpers, prompts, idempotency utils
│   └── downloads.sh              # curl download, .deb install, installer-script runner
└── logs/
    ├── install.log               # Full run log (every module, every level)
    ├── error.log                 # Only WARN/ERROR lines, for quick triage
    └── .state/                   # Module completion markers (auto-resume)
```

---

## Updating

Because every module is idempotent, "updating" your environment is the same
command as installing it:

```bash
cd ubuntu-dev-bootstrap
git pull
./install.sh
```

Already-installed tools are detected and skipped inside each module; on top
of that, a module marked "completed" in a previous run is skipped entirely
(see [Automatic resume](#automatic-resume-after-a-crash-or-lost-connection)).

One nuance worth knowing: if `git pull` brings in a change to a module's
*script logic* (not just a new tool version), that module will still be
skipped on a plain `./install.sh` run if it was already marked complete —
completion tracking is about "did this module finish," not "has its source
changed." To make sure an updated module actually re-runs, target it
explicitly:

```bash
./install.sh --only 09   # Re-run just the Docker module, e.g. after a
                          # daemon.json change in scripts/09-docker.sh
```

To force *every* module to reconsider its work after a big update:

```bash
./install.sh --force
```

---

## Adding a new module

1. Create `scripts/21-my-tool.sh` following the pattern of any existing module:

   ```bash
   #!/usr/bin/env bash
   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-utils.sh"
   CURRENT_MODULE="21-my-tool"
   trap 'utils::on_error $? $LINENO "$BASH_COMMAND"' ERR

   utils::print_banner "My Tool"

   if helpers::command_exists mytool; then
       log::info "mytool already installed"
   else
       helpers::apt_install mytool
   fi

   log::success "My Tool step complete"
   ```

2. `chmod +x scripts/21-my-tool.sh`
3. Register it in `install.sh` (position in `MODULE_ORDER` controls execution
   order — it doesn't have to match the filename's number):
   ```bash
   MODULE_NAMES[21]="My Tool"
   MODULE_ORDER+=(21)
   ```
4. Add any tunable versions/flags to `config/versions.conf`.
5. Test it in isolation: `./install.sh --only 21 --verbose`

Every module should:
- `source scripts/00-utils.sh` first (gives you logging, helpers, config)
- set `CURRENT_MODULE` for log tagging
- set an `ERR` trap
- check "is this already done?" before doing it (idempotency)
- log with `log::info` / `log::success` / `log::warn` / `log::error`

---

## Logging

- `logs/install.log` — every log line from every module, timestamped and tagged
  with the module name.
- `logs/error.log` — only `WARN` and `ERROR` lines, for quickly triaging a run
  without wading through the full log.
- `logs/.state/` — marker files used for two things: (1) module-level
  completion tracking that powers auto-resume (`module_<NN>_complete`), and
  (2) one-off steps with no reliable "is it installed?" check of their own
  (e.g. "database dev-user already created"). Delete a specific
  `module_<NN>_complete` file to make just that module re-run, or use
  `./install.sh --reset` to clear all of them at once.
- `--verbose` / `-v` additionally prints `DEBUG`-level messages to the
  terminal (they're always written to `install.log` regardless).

---

## Troubleshooting

**"Please do not run install.sh as root or with sudo directly"**
Run it as your normal user. It calls `sudo` internally only for the specific
commands that need root (apt, systemctl, etc.). Tools like fnm, bun, and
rustup must be installed as your user, not root.

**Docker commands say "permission denied" after installation**
You were added to the `docker` group, but group membership only applies to
new login sessions. Log out and back in, or run `newgrp docker`.

**`node`, `bun`, or `cargo` command not found right after install**
Restart your terminal (`exec $SHELL -l`) so the shell integration written to
`~/.bashrc` / `~/.zshrc` takes effect.

**A module failed partway through (e.g. network dropped mid-download)**
Just run `./install.sh` again. Completed modules are skipped automatically
and it retries exactly the module that failed — no flags needed. Check
`logs/error.log` first if you want to know what actually went wrong before
retrying (e.g. confirm your network is back).

**I want to force a specific module to redo its work**
`./install.sh --only 07` runs module 07 regardless of whether it was already
marked complete. `./install.sh --force` does the same for every module.
`./install.sh --reset` clears all completion markers if you want a totally
clean slate.

**Re-running the installer doesn't upgrade Node/npm/pnpm/Laravel installer**
That's intentional. Once a tool is installed, later runs leave its version
alone instead of silently upgrading it — only `apt-get upgrade` (module 01,
for the base OS) runs on every pass. To deliberately bump a version, edit the
relevant setting in `config/versions.conf` (e.g. `NODE_LTS_ALIAS`,
`PNPM_VERSION`) and force that module to re-run: `./install.sh --only 05`.

**PHP: `update-alternatives --config php` shows unexpected versions**
Run it manually to pick the active CLI PHP version; `config/versions.conf`
controls the default only for a first-time setup.

**Java: I want another version alongside 17**
Add it to `JAVA_VERSIONS` in `config/versions.conf` (e.g. `"17 21"`) and
re-run `./install.sh --only 10`. Switch the active version any time with
`sudo update-alternatives --config java`.

**SSH: I don't have an old key backup**
That's the default path — module 04 will just generate a brand new ed25519
key and print the public key for you to add to GitHub. It only asks about a
backup at all if you answer "yes" to having one.

**NVIDIA driver doesn't appear active after install**
A reboot is required for a freshly installed kernel driver to load.

**Antigravity IDE / TablePlus install step warns instead of installing**
Both vendors occasionally change their official Linux distribution method.
The module logs a warning with a link to the vendor's current official
download page when the configured repository/package name no longer matches.

**A base package (e.g. `eza`) fails to install on my Ubuntu release**
`helpers::apt_install` automatically falls back to installing packages one at
a time and skips any that don't exist on your release, logging a warning
instead of aborting the whole module — check `logs/error.log` to see exactly
which package(s) were skipped.

---

## Supported Ubuntu versions

Built and tested against **Ubuntu 24.04 LTS (Noble Numbat)**, and designed to
keep working on newer Ubuntu releases as they ship (24.10, 25.04, 25.10,
26.04, …): every module resolves the release codename/version at runtime via
`lsb_release`/`os-release` instead of hardcoding one, and apt installs
gracefully skip any individual package unavailable on your release rather
than failing the whole module. Running on a non-Ubuntu system prints a
warning but is not blocked.

---

## License

MIT License. Use, modify, and distribute freely.
