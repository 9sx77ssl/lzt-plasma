#!/bin/bash
set -e

REPO="9sx77ssl/lzt-plasma"
INSTALL_DIR="$HOME/.lzt-plasma-install"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ERROR_LOG="/tmp/lzt-plasma-install-error.log"

log_error() {
    echo "[$(date)] $1" >> "$ERROR_LOG"
}

report_error() {
    local msg="$1"
    log_error "$msg"
    echo "ERROR: $msg"
    echo "Error log: $ERROR_LOG"
    local issue_url="https://github.com/$REPO/issues/new?title=Install+Error&body=$(echo -n "$msg" | urlencode 2>/dev/null || echo "$msg" | sed 's/ /+/g')"
    echo "Report issue: $issue_url"
    rm -rf "$INSTALL_DIR"
    exit 1
}

detect_distro() {
    if [ -f /etc/arch-release ]; then
        echo "arch"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/fedora-release ]; then
        echo "fedora"
    elif [ -f /etc/almalinux-release ] || [ -f /etc/rocky-release ]; then
        echo "rhel"
    elif [ -f /etc/opensuse-release ]; then
        echo "opensuse"
    else
        echo "unknown"
    fi
}

DISTRO=$(detect_distro)

install_deps() {
    case "$DISTRO" in
        arch)
            if command -v pacman &>/dev/null; then
                sudo pacman -S --needed --noconfirm plasma-framework git curl wget 2>/dev/null || true
            fi
            ;;
        debian|ubuntu)
            if command -v apt &>/dev/null; then
                sudo apt update -qq 2>/dev/null || true
                sudo apt install -y plasma-framework git curl wget 2>/dev/null || true
            fi
            ;;
        fedora)
            if command -v dnf &>/dev/null; then
                sudo dnf install -y kf6-plasma-framework git curl wget 2>/dev/null || true
            fi
            ;;
        rhel)
            if command -v dnf &>/dev/null; then
                sudo dnf install -y kf6-plasma-framework git curl wget 2>/dev/null || true
            fi
            ;;
        opensuse)
            if command -v zypper &>/dev/null; then
                sudo zypper install -y plasma6-framework git curl wget 2>/dev/null || true
            fi
            ;;
    esac
}

if [ -d "$SCRIPT_DIR/.git" ] && [ "$(cd "$SCRIPT_DIR" && git remote get-url origin 2>/dev/null)" = "https://github.com/$REPO.git" ]; then
    cd "$SCRIPT_DIR"
    git pull --depth 1 2>/dev/null || true
else
    mkdir -p "$INSTALL_DIR" 2>/dev/null || report_error "Cannot create install directory"
    cd "$INSTALL_DIR" || report_error "Cannot enter install directory"

    if command -v git &>/dev/null; then
        if [ -d "lzt-plasma/.git" ]; then
            cd lzt-plasma
            git pull --depth 1 2>/dev/null || true
        else
            rm -rf lzt-plasma 2>/dev/null || true
            git clone --depth 1 "https://github.com/$REPO.git" lzt-plasma 2>/dev/null || report_error "Git clone failed"
            cd lzt-plasma || report_error "Cannot enter lzt-plasma directory"
        fi
    elif command -v curl &>/dev/null; then
        curl -sSLO "https://github.com/$REPO/archive/refs/heads/main.tar.gz" 2>/dev/null || report_error "Curl download failed"
        tar -xzf main.tar.gz 2>/dev/null || report_error "Tar extraction failed"
        rm main.tar.gz 2>/dev/null || true
        cd lzt-plasma-main || report_error "Cannot enter lzt-plasma-main directory"
    elif command -v wget &>/dev/null; then
        wget -q "https://github.com/$REPO/archive/refs/heads/main.tar.gz" 2>/dev/null || report_error "Wget download failed"
        tar -xzf main.tar.gz 2>/dev/null || report_error "Tar extraction failed"
        rm main.tar.gz 2>/dev/null || true
        cd lzt-plasma-main || report_error "Cannot enter lzt-plasma-main directory"
    else
        report_error "git, curl, or wget required"
    fi
fi

TOOL=""
if command -v kpackagetool6 &>/dev/null; then
    TOOL="kpackagetool6"
elif command -v kpackagetool5 &>/dev/null; then
    TOOL="kpackagetool5"
else
    install_deps
    if command -v kpackagetool6 &>/dev/null; then
        TOOL="kpackagetool6"
    elif command -v kpackagetool5 &>/dev/null; then
        TOOL="kpackagetool5"
    else
        report_error "kpackagetool not found. Install plasma-framework for your distribution."
    fi
fi

ICON_DIR="$HOME/.local/share/icons/hicolor/64x64/apps"
mkdir -p "$ICON_DIR" 2>/dev/null || true
cp package/contents/ui/images/lolzteam.png "$ICON_DIR/lztbalance.png" 2>/dev/null || true

$TOOL -t Plasma/Applet -u package/ 2>/dev/null || $TOOL -t Plasma/Applet -i package/ 2>/dev/null || report_error "kpackagetool install failed"

if command -v kbuildsycoca6 &>/dev/null; then
    kbuildsycoca6 2>/dev/null || true
elif command -v kbuildsycoca5 &>/dev/null; then
    kbuildsycoca5 2>/dev/null || true
fi

rm -rf "$INSTALL_DIR" 2>/dev/null || true
echo "Successfully installed. Restart Plasma:"
echo "  kquitapp6 plasmashell && kstart plasmashell"
