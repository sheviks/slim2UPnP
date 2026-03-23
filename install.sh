#!/bin/bash
# ============================================================================
# slim2UPnP installer
#
# Detects the distribution and init system (systemd / OpenRC),
# installs the binary and sets up the service.
#
# Usage:
#   sudo ./install.sh              # Install from build/slim2upnp
#   sudo ./install.sh /path/to/bin # Install a specific binary
#   sudo ./install.sh --uninstall  # Remove slim2upnp
# ============================================================================

set -e

BINARY_NAME="slim2upnp"
INSTALL_DIR="/usr/local/bin"
DIST_DIR="$(cd "$(dirname "$0")" && pwd)/dist"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; NC=''
fi

info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*"; }

# ============================================================================
# Detection
# ============================================================================

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="${ID}"
        DISTRO_NAME="${PRETTY_NAME:-${NAME}}"
    elif [ -f /etc/gentoo-release ]; then
        DISTRO_ID="gentoo"
        DISTRO_NAME="Gentoo"
    else
        DISTRO_ID="unknown"
        DISTRO_NAME="Unknown"
    fi

    # Detect GentooPlayer (Gentoo-based with specific customizations)
    if [ -f /etc/gentooplayer-release ] || [ -d /opt/gentooplayer ]; then
        DISTRO_ID="gentooplayer"
        DISTRO_NAME="GentooPlayer"
    fi

    # Detect AudioLinux
    if [ -f /etc/audiolinux-release ] || grep -qi "audiolinux" /etc/os-release 2>/dev/null; then
        DISTRO_ID="audiolinux"
        DISTRO_NAME="AudioLinux"
    fi
}

detect_init_system() {
    if command -v systemctl >/dev/null 2>&1 && pidof systemd >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    elif command -v rc-service >/dev/null 2>&1 || [ -d /etc/init.d ] && [ -f /sbin/openrc-run ]; then
        INIT_SYSTEM="openrc"
    elif [ -d /etc/init.d ]; then
        INIT_SYSTEM="sysvinit"
    else
        INIT_SYSTEM="unknown"
    fi
}

# ============================================================================
# Install
# ============================================================================

install_binary() {
    local src="$1"

    if [ ! -f "$src" ]; then
        error "Binary not found: $src"
        error "Build first: cmake -B build && cmake --build build"
        exit 1
    fi

    info "Installing $BINARY_NAME to $INSTALL_DIR/"
    install -m 755 "$src" "$INSTALL_DIR/$BINARY_NAME"
    info "Installed: $INSTALL_DIR/$BINARY_NAME"
}

install_systemd() {
    local service_file="$DIST_DIR/slim2upnp.service"
    local config_file="$DIST_DIR/slim2upnp.default"

    info "Setting up systemd service..."

    # Service file
    if [ -f "$service_file" ]; then
        cp "$service_file" /etc/systemd/system/slim2upnp.service
        info "Service file: /etc/systemd/system/slim2upnp.service"
    else
        error "Service file not found: $service_file"
        return 1
    fi

    # Configuration
    if [ ! -f /etc/default/slim2upnp ]; then
        cp "$config_file" /etc/default/slim2upnp
        info "Config file: /etc/default/slim2upnp (edit this!)"
    else
        warn "Config file already exists: /etc/default/slim2upnp (not overwritten)"
    fi

    systemctl daemon-reload
    info "systemd reloaded"

    echo ""
    info "Next steps:"
    echo "  1. Edit /etc/default/slim2upnp to set your renderer and LMS"
    echo "  2. sudo systemctl start slim2upnp"
    echo "  3. sudo systemctl enable slim2upnp   # auto-start at boot"
    echo ""
    echo "  Useful commands:"
    echo "    sudo systemctl status slim2upnp     # check status"
    echo "    sudo journalctl -u slim2upnp -f     # follow logs"
    echo "    sudo systemctl restart slim2upnp    # restart after config change"
}

install_openrc() {
    local init_file="$DIST_DIR/slim2upnp.openrc"
    local config_file="$DIST_DIR/slim2upnp.default"

    info "Setting up OpenRC service..."

    # Init script
    if [ -f "$init_file" ]; then
        cp "$init_file" /etc/init.d/slim2upnp
        chmod 755 /etc/init.d/slim2upnp
        info "Init script: /etc/init.d/slim2upnp"
    else
        error "Init script not found: $init_file"
        return 1
    fi

    # Configuration (OpenRC uses /etc/conf.d/)
    if [ ! -f /etc/conf.d/slim2upnp ]; then
        cp "$config_file" /etc/conf.d/slim2upnp
        info "Config file: /etc/conf.d/slim2upnp (edit this!)"
    else
        warn "Config file already exists: /etc/conf.d/slim2upnp (not overwritten)"
    fi

    echo ""
    info "Next steps:"
    echo "  1. Edit /etc/conf.d/slim2upnp to set your renderer and LMS"
    echo "  2. sudo rc-service slim2upnp start"
    echo "  3. sudo rc-update add slim2upnp default   # auto-start at boot"
    echo ""
    echo "  Useful commands:"
    echo "    sudo rc-service slim2upnp status     # check status"
    echo "    tail -f /var/log/slim2upnp.log       # follow logs"
    echo "    sudo rc-service slim2upnp restart    # restart after config change"
}

install_no_service() {
    warn "Init system not detected (or unsupported)."
    echo ""
    info "The binary is installed. Run manually:"
    echo "  $INSTALL_DIR/$BINARY_NAME -r \"My Renderer\" -s <LMS_IP>"
    echo ""
    echo "  Or create your own service/startup script."
}

# ============================================================================
# Uninstall
# ============================================================================

do_uninstall() {
    info "Uninstalling slim2UPnP..."

    # Stop service if running
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl stop slim2upnp 2>/dev/null || true
        systemctl disable slim2upnp 2>/dev/null || true
        rm -f /etc/systemd/system/slim2upnp.service
        systemctl daemon-reload
        info "systemd service removed"
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        rc-service slim2upnp stop 2>/dev/null || true
        rc-update del slim2upnp default 2>/dev/null || true
        rm -f /etc/init.d/slim2upnp
        info "OpenRC service removed"
    fi

    # Remove binary
    rm -f "$INSTALL_DIR/$BINARY_NAME"
    info "Binary removed: $INSTALL_DIR/$BINARY_NAME"

    # Keep config files (user may want them)
    if [ -f /etc/default/slim2upnp ]; then
        warn "Config kept: /etc/default/slim2upnp (remove manually if desired)"
    fi
    if [ -f /etc/conf.d/slim2upnp ]; then
        warn "Config kept: /etc/conf.d/slim2upnp (remove manually if desired)"
    fi

    info "Uninstall complete."
}

# ============================================================================
# Main
# ============================================================================

# Must be root
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root (sudo ./install.sh)"
    exit 1
fi

detect_distro
detect_init_system

echo "═══════════════════════════════════════════════════════"
echo "  slim2UPnP installer"
echo "═══════════════════════════════════════════════════════"
echo ""
info "Distribution: $DISTRO_NAME ($DISTRO_ID)"
info "Init system:  $INIT_SYSTEM"
echo ""

# Handle --uninstall
if [ "${1:-}" = "--uninstall" ]; then
    do_uninstall
    exit 0
fi

# Determine binary source
if [ -n "${1:-}" ] && [ -f "$1" ]; then
    BINARY_SRC="$1"
else
    # Auto-detect from build directory
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    BINARY_SRC="$SCRIPT_DIR/build/$BINARY_NAME"
fi

# Install binary
install_binary "$BINARY_SRC"

# Install service based on init system
case "$INIT_SYSTEM" in
    systemd)
        install_systemd
        ;;
    openrc)
        install_openrc
        ;;
    *)
        install_no_service
        ;;
esac

echo ""
info "Installation complete."
echo ""
echo "  Quick test (before configuring the service):"
echo "    $INSTALL_DIR/$BINARY_NAME --list-renderers"
echo "    $INSTALL_DIR/$BINARY_NAME -r \"My Renderer\" -s <LMS_IP>"
echo ""
