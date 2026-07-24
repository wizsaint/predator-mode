#!/bin/bash
# =============================================================================
# install-predator-mode.sh
# Installer for predator-mode — Acer Predator Helios Neo 16 power profile manager
# Supports Fedora (KDE) and CachyOS / any Arch-based distro
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Paths
SCRIPT_NAME="predator-mode"
INSTALL_DIR="${HOME}/.local/bin"
SCRIPT_PATH="${INSTALL_DIR}/${SCRIPT_NAME}"
SUDOERS_FILE="/etc/sudoers.d/platform_profile"
SERVICE_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SERVICE_DIR}/predator-profile.service"
PROFILE_PATH="/sys/firmware/acpi/platform_profile"
PROFILE_CHOICES="${PROFILE_PATH}_choices"

# Counters
STEPS_TOTAL=5
STEP=0

# =============================================================================
# Helpers
# =============================================================================

print_header() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  predator-mode installer${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

step() {
    STEP=$((STEP + 1))
    echo -e "\n${CYAN}${BOLD}[${STEP}/${STEPS_TOTAL}] $1${NC}"
}

ok() {
    echo -e "  ${GREEN}✔${NC} $1"
}

warn() {
    echo -e "  ${YELLOW}⚠${NC}  $1"
}

fail() {
    echo -e "\n${RED}${BOLD}✘ Error:${NC} $1"
    exit 1
}

backup_if_exists() {
    local FILE="$1"
    if [ -f "$FILE" ]; then
        local BACKUP="${FILE}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$FILE" "$BACKUP"
        warn "Existing file backed up to: $BACKUP"
    fi
}

# =============================================================================
# Step 1 — Compatibility check
# =============================================================================

check_compatibility() {
    step "Checking system compatibility"

    # Check sysfs profile interface exists
    if [ ! -f "$PROFILE_PATH" ]; then
        fail "ACPI platform_profile interface not found.\n  This script requires kernel support for platform profiles."
    fi
    ok "ACPI platform_profile interface found"

    # Check available profiles
    AVAILABLE=$(cat "$PROFILE_CHOICES" 2>/dev/null)
    if [ -z "$AVAILABLE" ]; then
        fail "Could not read platform_profile_choices."
    fi
    ok "Available profiles: ${AVAILABLE}"

    # Warn if balanced-performance isn't available (unexpected)
    if ! echo "$AVAILABLE" | grep -qw "balanced-performance"; then
        warn "'balanced-performance' not found in profile list — default will fall back to 'balanced'"
    fi

    # Check sudo access
    if ! sudo -v 2>/dev/null; then
        fail "sudo access required to install sudoers rule."
    fi
    ok "sudo access confirmed"

    # Detect distro
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        ok "Detected OS: ${PRETTY_NAME}"
    fi
}

# =============================================================================
# Step 2 — Install the predator-mode script
# =============================================================================

install_script() {
    step "Installing predator-mode script to ${INSTALL_DIR}"

    mkdir -p "$INSTALL_DIR"
    backup_if_exists "$SCRIPT_PATH"

    cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/bash

PROFILE_PATH="/sys/firmware/acpi/platform_profile"
AVAILABLE=$(cat "${PROFILE_PATH}_choices" 2>/dev/null)
CONFIG_DIR="${HOME}/.config/predator-mode"
CONFIG_FILE="${CONFIG_DIR}/config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

get_default() {
    if [ -f "$CONFIG_FILE" ]; then
        grep -m1 "^default=" "$CONFIG_FILE" | cut -d'=' -f2
    else
        echo "balanced-performance"
    fi
}

show_help() {
    echo -e "${BOLD}predator-mode${NC} — Acer Predator platform profile switcher"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  predator-mode [profile]       Set a profile (uses saved default if none given)"
    echo "  predator-mode -s              Show current profile"
    echo "  predator-mode -l              List available profiles"
    echo "  predator-mode -d [profile]    Set a new default profile"
    echo "  predator-mode -h              Show this help"
}

show_status() {
    CURRENT=$(cat "$PROFILE_PATH")
    DEFAULT=$(get_default)
    echo -e "Current profile: ${GREEN}${BOLD}${CURRENT}${NC}"
    echo -e "Default profile: ${CYAN}${DEFAULT}${NC}"
}

show_list() {
    CURRENT=$(cat "$PROFILE_PATH")
    DEFAULT=$(get_default)
    echo -e "${BOLD}Available profiles:${NC}"
    for p in $AVAILABLE; do
        LINE="    $p"
        [ "$p" = "$CURRENT" ] && LINE="${GREEN}  ▶ $p (active)${NC}"
        [ "$p" = "$DEFAULT" ] && LINE="${LINE} ${YELLOW}[default]${NC}"
        echo -e "$LINE"
    done
}

set_default() {
    local PROFILE="$1"

    if ! echo "$AVAILABLE" | grep -qw "$PROFILE"; then
        echo -e "${RED}Error:${NC} '$PROFILE' is not a valid profile."
        echo -e "Run ${CYAN}predator-mode -l${NC} to see available profiles."
        exit 1
    fi

    mkdir -p "$CONFIG_DIR"
    echo "default=${PROFILE}" > "$CONFIG_FILE"
    echo -e "Default profile set to: ${CYAN}${BOLD}${PROFILE}${NC}"
    echo -e "The systemd service will use this on next login."
}

set_profile() {
    local PROFILE="$1"

    if ! echo "$AVAILABLE" | grep -qw "$PROFILE"; then
        echo -e "${RED}Error:${NC} '$PROFILE' is not a valid profile."
        echo -e "Run ${CYAN}predator-mode -l${NC} to see available profiles."
        exit 1
    fi

    if echo "$PROFILE" | sudo tee "$PROFILE_PATH" > /dev/null; then
        echo -e "Profile set to: ${GREEN}${BOLD}${PROFILE}${NC}"
    else
        echo -e "${RED}Error:${NC} Failed to set profile. Check your sudoers rule."
        exit 1
    fi
}

case "${1}" in
    -h|--help)    show_help ;;
    -s|--status)  show_status ;;
    -l|--list)    show_list ;;
    -d|--default)
        if [ -z "$2" ]; then
            echo -e "Current default: ${CYAN}$(get_default)${NC}"
        else
            set_default "$2"
        fi
        ;;
    "") set_profile "$(get_default)" ;;
    *)  set_profile "$1" ;;
esac
EOF

    chmod +x "$SCRIPT_PATH"
    ok "Script installed: ${SCRIPT_PATH}"

    # Verify ~/.local/bin is in PATH
    if ! echo "$PATH" | grep -q "${HOME}/.local/bin"; then
        warn "~/.local/bin is not in your PATH."
        warn "Add the following to your ~/.bashrc or ~/.zshrc:"
        warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    else
        ok "~/.local/bin is in PATH"
    fi
}

# =============================================================================
# Step 3 — Install sudoers rule
# =============================================================================

install_sudoers() {
    step "Installing sudoers rule"

    SUDOERS_LINE="${USER} ALL=(ALL) NOPASSWD: /usr/bin/tee /sys/firmware/acpi/platform_profile"
    TMPFILE=$(mktemp)

    echo "$SUDOERS_LINE" > "$TMPFILE"

    # Validate syntax before installing
    if ! sudo visudo -c -f "$TMPFILE" > /dev/null 2>&1; then
        rm -f "$TMPFILE"
        fail "Sudoers syntax validation failed. This should not happen — please report this."
    fi

    sudo cp "$TMPFILE" "$SUDOERS_FILE"
    sudo chmod 0440 "$SUDOERS_FILE"
    rm -f "$TMPFILE"

    ok "Sudoers rule installed: ${SUDOERS_FILE}"
    ok "Rule: ${SUDOERS_LINE}"
}

# =============================================================================
# Step 4 — Install systemd user service
# =============================================================================

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

# =============================================================================
# Step 5 — Enable and start the service
# =============================================================================

enable_service() {
    step "Enabling systemd user service"

    systemctl --user daemon-reload

    # Disable first in case it was already enabled (clean re-enable)
    systemctl --user disable predator-profile.service > /dev/null 2>&1 || true
    systemctl --user enable predator-profile.service

    # Start it now too so we don't need to re-login to test
    systemctl --user restart predator-profile.service

    ok "Service enabled and started"

    # Brief pause to let the service settle then verify
    sleep 3
    CURRENT=$(cat "$PROFILE_PATH" 2>/dev/null)
    ok "Current profile: ${CURRENT}"
}

# =============================================================================
# Summary
# =============================================================================

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
    echo "  predator-mode -l           List all profiles"
    echo "  predator-mode -s           Show current + default"
    echo "  predator-mode -d [profile] Set a new default"
    echo "  predator-mode -h           Help"
    echo ""
    echo -e "${BOLD}Service status:${NC}"
    systemctl --user status predator-profile.service --no-pager -l | grep -E "Active|Main PID|predator" | sed 's/^/  /'
    echo ""
}

# =============================================================================
# Uninstall
# =============================================================================

uninstall() {
    echo -e "\n${YELLOW}${BOLD}Uninstalling predator-mode...${NC}\n"

    systemctl --user disable --now predator-profile.service 2>/dev/null && ok "Service disabled" || warn "Service was not active"
    rm -f "$SERVICE_FILE"   && ok "Removed: ${SERVICE_FILE}"   || warn "Not found: ${SERVICE_FILE}"
    rm -f "$SCRIPT_PATH"    && ok "Removed: ${SCRIPT_PATH}"    || warn "Not found: ${SCRIPT_PATH}"
    sudo rm -f "$SUDOERS_FILE" && ok "Removed: ${SUDOERS_FILE}" || warn "Not found: ${SUDOERS_FILE}"
    systemctl --user daemon-reload

    echo -e "\n${GREEN}Done.${NC} Config file at ~/.config/predator-mode/ was left intact.\n"
    exit 0
}

# =============================================================================
# Entry point
# =============================================================================

case "${1}" in
    --uninstall|-u)
        uninstall
        ;;
    --help|-h)
        echo "Usage: $0 [--uninstall]"
        echo "  (no args)     Run the installer"
        echo "  --uninstall   Remove everything"
        exit 0
        ;;
    "")
        print_header
        check_compatibility
        install_script
        install_sudoers
        install_service
        enable_service
        print_summary
        ;;
    *)
        fail "Unknown option: $1. Use --help for usage."
        ;;
esac
