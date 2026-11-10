#!/bin/bash
# install-predator-mode.sh — install, update or remove predator-mode
# https://github.com/wizsaint/predator-mode
#
#   bash install-predator-mode.sh              install, or update an existing install
#   bash install-predator-mode.sh --uninstall  remove everything
#
# Safe to re-run. Each component (script, sudoers rule, login service) is compared
# with what is installed and only touched if it differs, so re-running the
# installer *is* the update. The login service is installed but never switched on
# or off for you; enable it yourself with: predator-mode --enable

set -eu

REPO_RAW="https://raw.githubusercontent.com/wizsaint/predator-mode/main"

BIN_NAME="predator-mode"
BIN_DIR="$HOME/.local/bin"
BIN_PATH="$BIN_DIR/$BIN_NAME"
UNIT_NAME="predator-profile.service"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT_PATH="$UNIT_DIR/$UNIT_NAME"
CONFIG_DIR="$HOME/.config/predator-mode"
SUDOERS_FILE="/etc/sudoers.d/platform_profile"
PROFILE_PATH="/sys/firmware/acpi/platform_profile"

USER_NAME=$(id -un)
WORK=""
CHANGED=""
STEP=0
STEPS=4

# ── Output ────────────────────────────────────────────────────────────────────

BOLD='' DIM='' GREEN='' YELLOW='' CYAN='' RED='' NC=''
if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
    BOLD=$'\033[1m' DIM=$'\033[2m' GREEN=$'\033[32m' YELLOW=$'\033[33m'
    CYAN=$'\033[36m' RED=$'\033[31m' NC=$'\033[0m'
fi

step() { STEP=$((STEP + 1)); printf '\n%s[%d/%d] %s%s\n' "$BOLD$CYAN" "$STEP" "$STEPS" "$1" "$NC"; }
ok()   { printf '  %s✔%s %s\n' "$GREEN" "$NC" "$*"; }
act()  { printf '  %s→%s %s\n' "$CYAN" "$NC" "$*"; }
note() { printf '  %s•%s %s\n' "$DIM" "$NC" "$*"; }
warn() { printf '  %s⚠%s %s\n' "$YELLOW" "$NC" "$*"; }
fail() { printf '\n%s✘ Error:%s %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: bash install-predator-mode.sh [--uninstall]

  (no option)   Install predator-mode, or update an existing installation.
                Safe to re-run: only components that differ are changed.
  --uninstall   Remove predator-mode, its sudoers rule and its login service.
  -h, --help    Show this help.
EOF
}

# ── Helpers ───────────────────────────────────────────────────────────────────

have() { command -v "$1" >/dev/null 2>&1; }

# run_as 1 CMD… runs through sudo, run_as 0 CMD… runs as the current user
run_as() { local priv=$1; shift; if [ "$priv" = 1 ]; then sudo "$@"; else "$@"; fi; }

refuse_root() {
    if [ "$(id -u)" -eq 0 ]; then
        fail "don't run this as root or with sudo. It sets up files in your home directory and calls sudo itself where needed."
    fi
}

read_version() { grep -m1 '^VERSION=' "$1" 2>/dev/null | cut -d'"' -f2 || true; }

verb() { if [ "$1" = missing ]; then echo installed; else echo updated; fi; }

on_path() {
    case ":$PATH:" in *":$BIN_DIR:"*) return 0 ;; esac
    # The installer runs under bash; the login shell may know better (e.g. fish_add_path)
    local sh=${SHELL:-}
    [ -x "$sh" ] || return 1
    timeout 5 "$sh" -lc "command -v $BIN_NAME" >/dev/null 2>&1
}

build_sudoers() {
    cat <<EOF
# Managed by install-predator-mode.sh: lets $USER_NAME switch the platform profile without a password
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/tee $PROFILE_PATH
EOF
}

build_unit() {
    cat <<'EOF'
# Managed by install-predator-mode.sh
[Unit]
Description=Apply the default Predator power profile after login
After=graphical-session.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 2
ExecStart=%h/.local/bin/predator-mode
RemainAfterExit=yes

[Install]
WantedBy=graphical-session.target
EOF
}

# same_file NEW EXISTING USE_SUDO — true if EXISTING has exactly NEW's content
same_file() {
    if [ "$3" = 1 ]; then
        sudo cat "$2" 2>/dev/null | cmp -s - "$1"
    else
        cmp -s "$1" "$2"
    fi
}

# place SRC DEST MODE USE_SUDO BACKUP
# Installs SRC at DEST atomically (copy next to it, then rename). With BACKUP=1 an
# existing DEST is first copied to DEST.bak (a single backup, overwritten each time).
place() {
    local src=$1 dest=$2 mode=$3 priv=$4 backup=$5 owner=""
    if [ "$priv" = 1 ]; then owner="-o root -g root"; fi
    if [ "$backup" = 1 ] && [ -e "$dest" ]; then
        act "cp -p $dest $dest.bak"
        run_as "$priv" cp -p "$dest" "$dest.bak"
    fi
    act "install -m $mode ${owner:+$owner }$dest"
    # shellcheck disable=SC2086  # $owner is meant to split into separate arguments
    run_as "$priv" install -m "$mode" $owner "$src" "$dest.new"
    run_as "$priv" mv -f "$dest.new" "$dest"
}

# ── 1. Pre-flight ─────────────────────────────────────────────────────────────

preflight() {
    step "Pre-flight checks"
    refuse_root
    ok "running as '$USER_NAME' (home: $HOME)"

    if [ ! -r "$PROFILE_PATH" ]; then
        fail "$PROFILE_PATH not found. This kernel does not expose ACPI platform profiles (needs Linux 5.12+ and a supported laptop)."
    fi
    ok "kernel exposes $PROFILE_PATH"

    local choices
    choices=$(cat "${PROFILE_PATH}_choices" 2>/dev/null || true)
    [ -n "$choices" ] || fail "could not read ${PROFILE_PATH}_choices"
    ok "available profiles: $choices"
    case " $choices " in
        *" balanced-performance "*) ;;
        *) warn "'balanced-performance' is not offered here; the default will fall back to 'balanced'" ;;
    esac

    have systemctl || fail "systemd is required (systemctl not found)"
    systemctl --user show-environment >/dev/null 2>&1 \
        || fail "no systemd user session. Run this from a normal desktop login, not from su or a bare TTY."
    ok "systemd user session available"

    have sudo || fail "sudo is required (it is used to install the sudoers rule)"
    [ -x /usr/bin/tee ] || fail "/usr/bin/tee not found (the sudoers rule is tied to that path)"
    note "sudo is needed once, to install and check $SUDOERS_FILE"
    sudo -v || fail "sudo authentication failed"
    ok "sudo access confirmed"
}

# ── 2. Get the script ─────────────────────────────────────────────────────────

fetch_source() {
    step "Getting predator-mode"
    local self="${BASH_SOURCE[0]:-}" here=""
    if [ -f "$self" ]; then here=$(cd "$(dirname "$self")" && pwd); fi

    if [ -n "$here" ] && [ -d "$here/.git" ] && [ -f "$here/$BIN_NAME" ]; then
        cp "$here/$BIN_NAME" "$WORK/$BIN_NAME"
        ok "using the copy in this git checkout: $here/$BIN_NAME"
    else
        have curl || fail "curl is required to download predator-mode"
        act "curl -fsSL $REPO_RAW/$BIN_NAME"
        curl -fsSL "$REPO_RAW/$BIN_NAME" -o "$WORK/$BIN_NAME" \
            || fail "download failed. Check your internet connection."
        ok "downloaded $(wc -c < "$WORK/$BIN_NAME") bytes"
    fi

    head -n1 "$WORK/$BIN_NAME" | grep -q '^#!/bin/bash' \
        || fail "the downloaded file is not a bash script (wrong URL, or an error page?)"
    bash -n "$WORK/$BIN_NAME" || fail "the downloaded script has a syntax error; not installing it"
    NEW_VERSION=$(read_version "$WORK/$BIN_NAME")
    [ -n "$NEW_VERSION" ] || fail "could not read VERSION from the downloaded script"
    ok "valid script, version $NEW_VERSION"
}

# ── 3. Inspect ────────────────────────────────────────────────────────────────

inspect() {
    step "Inspecting current installation"

    local old_version old_label

    # Script
    if [ -e "$BIN_PATH" ]; then
        old_version=$(read_version "$BIN_PATH")
        old_label=${old_version:+v$old_version}
        old_label=${old_label:-an older version}
        if cmp -s "$WORK/$BIN_NAME" "$BIN_PATH"; then
            BIN_STATE=current
            note "script    $BIN_PATH: v$NEW_VERSION, up to date"
        else
            BIN_STATE=outdated
            if [ "$old_version" = "$NEW_VERSION" ]; then
                note "script    $BIN_PATH: v$NEW_VERSION but the content differs (local edits?), will be replaced"
            else
                note "script    $BIN_PATH: $old_label installed, will update to v$NEW_VERSION"
            fi
        fi
    else
        BIN_STATE=missing
        note "script    not installed, will install v$NEW_VERSION to $BIN_PATH"
    fi

    # Sudoers rule
    build_sudoers > "$WORK/sudoers"
    if sudo test -e "$SUDOERS_FILE"; then
        if same_file "$WORK/sudoers" "$SUDOERS_FILE" 1; then
            SUDO_STATE=current
            note "sudoers   $SUDOERS_FILE: up to date"
        else
            SUDO_STATE=outdated
            note "sudoers   $SUDOERS_FILE: differs from the expected rule, will be rewritten"
        fi
    else
        SUDO_STATE=missing
        note "sudoers   not installed, will create $SUDOERS_FILE"
    fi

    # Login service
    build_unit > "$WORK/unit"
    ENABLED_STATE=$(systemctl --user is-enabled "$UNIT_NAME" 2>/dev/null || true)
    if [ -e "$UNIT_PATH" ]; then
        if same_file "$WORK/unit" "$UNIT_PATH" 0; then
            UNIT_STATE=current
            note "service   $UNIT_PATH: up to date (${ENABLED_STATE:-not enabled})"
        else
            UNIT_STATE=outdated
            note "service   $UNIT_PATH: differs from the expected unit, will be rewritten (${ENABLED_STATE:-not enabled})"
        fi
    else
        UNIT_STATE=missing
        note "service   not installed, will create $UNIT_PATH"
    fi
}

# ── 4. Apply ──────────────────────────────────────────────────────────────────

apply() {
    step "Applying changes"

    # Script
    if [ "$BIN_STATE" = current ]; then
        ok "script already up to date"
    else
        mkdir -p "$BIN_DIR"
        place "$WORK/$BIN_NAME" "$BIN_PATH" 0755 0 1
        ok "script $(verb "$BIN_STATE") (v$NEW_VERSION)"
        CHANGED="$CHANGED script"
    fi

    # Sudoers rule: always syntax-checked before it goes live
    if [ "$SUDO_STATE" = current ]; then
        ok "sudoers rule already up to date"
    else
        act "visudo -c -f (syntax check before installing)"
        sudo visudo -c -f "$WORK/sudoers" >/dev/null 2>&1 \
            || fail "the generated sudoers rule failed validation; nothing was installed. Please report this."
        place "$WORK/sudoers" "$SUDOERS_FILE" 0440 1 0
        ok "sudoers rule $(verb "$SUDO_STATE")"
        CHANGED="$CHANGED sudoers"
    fi

    # Login service
    if [ "$UNIT_STATE" = current ]; then
        ok "login service already up to date"
    else
        mkdir -p "$UNIT_DIR"
        place "$WORK/unit" "$UNIT_PATH" 0644 0 1
        act "systemctl --user daemon-reload"
        systemctl --user daemon-reload
        ok "login service $(verb "$UNIT_STATE")"
        CHANGED="$CHANGED service"
    fi

    # Opt-in: the installer never switches the login service on or off
    if [ "$ENABLED_STATE" = enabled ]; then
        ok "login service is enabled (left as it is)"
    else
        note "login service is not enabled (opt-in). Turn it on with: predator-mode --enable"
    fi
}

summary() {
    printf '\n%s━━ Done ━━%s\n' "$BOLD" "$NC"
    if [ -z "$CHANGED" ]; then
        ok "already up to date, nothing was changed"
    else
        ok "changed:$CHANGED"
    fi
    if [ -n "$CHANGED" ]; then
        note "your current power profile was not touched"
    fi

    printf '\n%sStatus%s\n' "$BOLD" "$NC"
    "$BIN_PATH" --version | sed 's/^/  /' || true
    "$BIN_PATH" -s | sed 's/^/  /' || true

    if ! on_path; then
        printf '\n'
        warn "$BIN_DIR is not on your PATH, so '$BIN_NAME' won't be found by name yet:"
        case "$(basename "${SHELL:-bash}")" in
            fish) warn "run:  fish_add_path ~/.local/bin" ;;
            zsh)  warn "add to ~/.zshrc:   export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
            *)    warn "add to ~/.bashrc:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
        esac
    fi
    printf '\nRun %s%s -h%s for usage.\n' "$BOLD" "$BIN_NAME" "$NC"
}

do_install() {
    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT
    printf '%s━━ predator-mode installer ━━%s\n' "$BOLD" "$NC"
    preflight
    fetch_source
    inspect
    apply
    summary
}

# ── Uninstall ─────────────────────────────────────────────────────────────────

remove() { # remove PATH USE_SUDO
    if run_as "$2" test -e "$1"; then
        run_as "$2" rm -f "$1"
        ok "removed $1"
    else
        note "not found: $1"
    fi
}

do_uninstall() {
    printf '%s━━ predator-mode uninstaller ━━%s\n\n' "$BOLD" "$NC"
    refuse_root
    have sudo || fail "sudo is required to remove $SUDOERS_FILE"
    sudo -v || fail "sudo authentication failed"

    if systemctl --user disable --now "$UNIT_NAME" >/dev/null 2>&1; then
        ok "login service disabled and stopped"
    else
        note "login service was not enabled"
    fi
    remove "$UNIT_PATH" 0
    remove "$UNIT_PATH.bak" 0
    systemctl --user daemon-reload || true
    remove "$BIN_PATH" 0
    remove "$BIN_PATH.bak" 0
    remove "$SUDOERS_FILE" 1

    if [ -d "$CONFIG_DIR" ]; then
        local reply=""
        if [ -t 0 ]; then
            read -rp "  Also delete your saved settings in $CONFIG_DIR? [y/N] " reply || true
        fi
        if [[ "$reply" =~ ^[Yy]$ ]]; then
            rm -rf "$CONFIG_DIR"
            ok "removed $CONFIG_DIR"
        else
            note "kept $CONFIG_DIR"
        fi
    fi

    printf '\n'
    ok "done. Your current power profile was not changed."
}

# ── Entry point ───────────────────────────────────────────────────────────────

case "${1:-}" in
    "")              do_install ;;
    --uninstall|-u)  do_uninstall ;;
    -h|--help)       usage ;;
    *)               usage >&2; exit 2 ;;
esac
