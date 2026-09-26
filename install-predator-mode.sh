#!/bin/bash
# =============================================================================
# install-predator-mode.sh
# Installer for predator-mode — Acer Predator Helios Neo 16 power profile manager
# Supports Fedora (KDE) and CachyOS / any Arch-based distro
# =============================================================================

VERSION="1.2.0"
REPO_RAW="https://raw.githubusercontent.com/wizsaint/predator-mode/main"

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_NAME="predator-mode"
INSTALL_DIR="${HOME}/.local/bin"
SCRIPT_PATH="${INSTALL_DIR}/${SCRIPT_NAME}"
SUDOERS_FILE="/etc/sudoers.d/platform_profile"
SERVICE_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SERVICE_DIR}/predator-profile.service"
CONFIG_DIR="${HOME}/.config/predator-mode"
PROFILE_PATH="/sys/firmware/acpi/platform_profile"
PROFILE_CHOICES="${PROFILE_PATH}_choices"

STEPS_TOTAL=5
STEP=0

# ── Helpers ───────────────────────────────────────────────────────────────────

print_header() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  predator-mode installer ${CYAN}v${VERSION}${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

step() {
    STEP=$((STEP + 1))
    echo -e "\n${CYAN}${BOLD}[${STEP}/${STEPS_TOTAL}] $1${NC}"
}

ok()   { echo -e "  ${GREEN}✔${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "\n${RED}${BOLD}✘ Error:${NC} $1"; exit 1; }

backup_if_exists() {
    local FILE="$1"
    if [ -f "$FILE" ]; then
        local BACKUP="${FILE}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$FILE" "$BACKUP"
        warn "Existing file backed up to: $BACKUP"
    fi
}

detect_shell() {
    basename "$(getent passwd "$USER" | cut -d: -f7)"
}

# ── Step 1 — Compatibility check ──────────────────────────────────────────────

check_compatibility() {
    step "Checking system compatibility"

    if [ ! -f "$PROFILE_PATH" ]; then
        fail "ACPI platform_profile interface not found.\n  This script requires kernel support for platform profiles."
    fi
    ok "ACPI platform_profile interface found"

    local AVAILABLE
    AVAILABLE=$(cat "$PROFILE_CHOICES" 2>/dev/null)
    if [ -z "$AVAILABLE" ]; then
        fail "Could not read platform_profile_choices."
    fi
    ok "Available profiles: ${AVAILABLE}"

    if ! echo "$AVAILABLE" | grep -qw "balanced-performance"; then
        warn "'balanced-performance' not in profile list — default will fall back to 'balanced'"
    fi

    if ! sudo -v 2>/dev/null; then
        fail "sudo access required to install sudoers rule."
    fi
    ok "sudo access confirmed"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        ok "Detected OS: ${PRETTY_NAME}"
    fi

    if ! command -v curl &>/dev/null; then
        fail "curl is required but not installed. Install it and re-run."
    fi
    ok "curl found"
}

# ── Step 2 — Download and install the predator-mode script ───────────────────

install_script() {
    step "Downloading predator-mode script from GitHub"

    mkdir -p "$INSTALL_DIR"
    backup_if_exists "$SCRIPT_PATH"

    local DOWNLOAD_URL="${REPO_RAW}/predator-mode"
    if ! curl -fsSL "$DOWNLOAD_URL" -o "$SCRIPT_PATH"; then
        fail "Failed to download predator-mode from:\n  ${DOWNLOAD_URL}\n  Check your internet connection."
    fi

    chmod +x "$SCRIPT_PATH"
    ok "Script downloaded and installed: ${SCRIPT_PATH}"

    local SHELL_NAME
    SHELL_NAME=$(detect_shell)

    if ! echo "$PATH" | grep -q "${HOME}/.local/bin"; then
        warn "~/.local/bin is not in your PATH."
        case "$SHELL_NAME" in
            fish) warn "Run: fish_add_path ~/.local/bin" ;;
            zsh)  warn "Add to ~/.zshrc:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
            *)    warn "Add to ~/.bashrc: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
        esac
    else
        ok "~/.local/bin is in PATH"
    fi
}

# ── Step 3 — Install sudoers rule ─────────────────────────────────────────────

install_sudoers() {
    step "Installing sudoers rule"

    local SUDOERS_LINE="${USER} ALL=(ALL) NOPASSWD: /usr/bin/tee /sys/firmware/acpi/platform_profile"
    local TMPFILE
    TMPFILE=$(mktemp)

    echo "$SUDOERS_LINE" > "$TMPFILE"

    if ! sudo visudo -c -f "$TMPFILE" > /dev/null 2>&1; then
        rm -f "$TMPFILE"
        fail "Sudoers syntax validation failed. Please report this."
    fi

    sudo cp "$TMPFILE" "$SUDOERS_FILE"
    sudo chmod 0440 "$SUDOERS_FILE"
    rm -f "$TMPFILE"

    ok "Sudoers rule installed: ${SUDOERS_FILE}"
    ok "Rule: ${SUDOERS_LINE}"
}

# ── Step 4 — Install systemd user service ────────────────────────────────────

install_service() {
    step "Installing systemd user service"

    mkdir -p "$SERVICE_DIR"
    backup_if_exists "$SERVICE_FILE"

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Set Predator power profile after login
After=graphical-session.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 2
ExecStart=${SCRIPT_PATH}
RemainAfterExit=yes

[Install]
WantedBy=graphical-session.target
EOF

    ok "Service file installed: ${SERVICE_FILE}"
}

# ── Step 5 — Enable and start the service ────────────────────────────────────

activate_service() {
    step "Enabling systemd user service"

    systemctl --user daemon-reload
    systemctl --user disable predator-profile.service > /dev/null 2>&1 || true
    systemctl --user enable predator-profile.service
    systemctl --user restart predator-profile.service

    ok "Service enabled and started"

    # Wait for service ExecStartPre (2s) + execution to complete
    sleep 3
    local CURRENT
    CURRENT=$(cat "$PROFILE_PATH" 2>/dev/null)
    ok "Current profile: ${CURRENT}"
}

# ── Summary ───────────────────────────────────────────────────────────────────

print_summary() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}  Installation complete!${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Quick reference:${NC}"
    echo "  predator-mode              Apply default profile"
    echo "  predator-mode quiet        Switch to quiet"
    echo "  predator-mode performance  Switch to turbo"
    echo "  predator-mode -c           Cycle to next profile"
    echo "  predator-mode -l           List all profiles"
    echo "  predator-mode -s           Show current + default"
    echo "  predator-mode -d [profile] Set a new default"
    echo "  predator-mode --enable     Enable login service"
    echo "  predator-mode --disable    Disable login service"
    echo "  predator-mode --service    Show service status"
    echo "  predator-mode --update     Update to latest version"
    echo "  predator-mode -h           Help"
    echo ""
    echo -e "${BOLD}Service status:${NC}"
    systemctl --user status predator-profile.service --no-pager -l \
        | grep -E "Active|Main PID|predator" | sed 's/^/  /'
    echo ""
}

# ── Uninstall ─────────────────────────────────────────────────────────────────

uninstall() {
    echo -e "\n${YELLOW}${BOLD}Uninstalling predator-mode...${NC}\n"

    systemctl --user disable --now predator-profile.service 2>/dev/null \
        && ok "Service disabled" || warn "Service was not active"

    rm -f "$SERVICE_FILE"      && ok "Removed: ${SERVICE_FILE}"   || warn "Not found: ${SERVICE_FILE}"
    rm -f "$SCRIPT_PATH"       && ok "Removed: ${SCRIPT_PATH}"    || warn "Not found: ${SCRIPT_PATH}"
    sudo rm -f "$SUDOERS_FILE" && ok "Removed: ${SUDOERS_FILE}"   || warn "Not found: ${SUDOERS_FILE}"

    systemctl --user daemon-reload

    if [ -d "$CONFIG_DIR" ]; then
        echo ""
        read -rp "  Remove config directory ($CONFIG_DIR)? [y/N] " REPLY
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            rm -rf "$CONFIG_DIR" && ok "Removed: ${CONFIG_DIR}"
        else
            ok "Config directory kept at: ${CONFIG_DIR}"
        fi
    fi

    echo -e "\n${GREEN}Done.${NC}\n"
    exit 0
}

# ── Entry point ───────────────────────────────────────────────────────────────

case "${1}" in
    --uninstall|-u)
        uninstall
        ;;
    --help|-h)
        echo "predator-mode installer v${VERSION}"
        echo ""
        echo "Usage: $0 [option]"
        echo "  (no args)     Run the installer"
        echo "  --uninstall   Remove everything"
        echo "  --version     Print version"
        exit 0
        ;;
    --version|-v)
        echo "predator-mode installer v${VERSION}"
        exit 0
        ;;
    "")
        print_header
        check_compatibility
        install_script
        install_sudoers
        install_service
        activate_service
        print_summary
        ;;
    *)
        fail "Unknown option: $1. Use --help for usage."
        ;;
esac
