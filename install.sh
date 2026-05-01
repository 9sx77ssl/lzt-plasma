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
    elif [ -f /etc/artix-release ]; then
        echo "arch"
    elif [ -f /etc/endeavouros-release ]; then
        echo "arch"
    elif [ -f /etc/manjaro-release ]; then
        echo "arch"
    elif [ -f /etc/garuda-release ]; then
        echo "arch"
    elif [ -f /etc/cachyos-release ]; then
        echo "arch"
    elif [ -f /etc/gentoo-release ]; then
        echo "gentoo"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/lsb-release ] && grep -q "Ubuntu" /etc/lsb-release 2>/dev/null; then
        echo "ubuntu"
    elif [ -f /etc/lsb-release ] && grep -q "Mint" /etc/lsb-release 2>/dev/null; then
        echo "debian"
    elif [ -f /etc/lsb-release ] && grep -q "Pop" /etc/lsb-release 2>/dev/null; then
        echo "ubuntu"
    elif [ -f /etc/fedora-release ]; then
        echo "fedora"
    elif [ -f /etc/almalinux-release ] || [ -f /etc/rocky-release ]; then
        echo "rhel"
    elif [ -f /etc/centos-release ]; then
        echo "rhel"
    elif [ -f /etc/opensuse-release ]; then
        echo "opensuse"
    elif [ -f /etc/kdeneon-release ]; then
        echo "ubuntu"
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
        gentoo)
            if command -v emerge &>/dev/null; then
                sudo emerge -q kde-plasma/plasma-framework dev-vcs/git net-misc/curl net-misc/wget 2>/dev/null || true
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

restart_plasma() {
    if command -v kquitapp6 &>/dev/null && command -v kstart &>/dev/null; then
        kquitapp6 plasmashell 2>/dev/null || true
        sleep 2
        kstart plasmashell 2>/dev/null || true
    elif command -v plasmashell &>/dev/null; then
        plasmashell --replace 2>/dev/null || true
    fi
}

if [ -d "$SCRIPT_DIR/.git" ] && [ "$(cd "$SCRIPT_DIR" && git remote get-url origin 2>/dev/null)" = "https://github.com/$REPO.git" ]; then
    cd "$SCRIPT_DIR"
    git pull --depth 1 2>/dev/null
else
    mkdir -p "$INSTALL_DIR" 2>/dev/null || report_error "Cannot create install directory"
    cd "$INSTALL_DIR" || report_error "Cannot enter install directory"

    if command -v git &>/dev/null; then
        if [ -d "lzt-plasma/.git" ]; then
            cd lzt-plasma
            git pull --depth 1 2>/dev/null
        else
            rm -rf lzt-plasma 2>/dev/null
            git clone --depth 1 "https://github.com/$REPO.git" lzt-plasma 2>/dev/null || report_error "Git clone failed"
            cd lzt-plasma || report_error "Cannot enter lzt-plasma directory"
        fi
    elif command -v curl &>/dev/null; then
        curl -sSLO "https://github.com/$REPO/archive/refs/heads/main.tar.gz" 2>/dev/null || report_error "Curl download failed"
        tar -xzf main.tar.gz 2>/dev/null || report_error "Tar extraction failed"
        rm main.tar.gz 2>/dev/null
        cd lzt-plasma-main || report_error "Cannot enter lzt-plasma-main directory"
    elif command -v wget &>/dev/null; then
        wget -q "https://github.com/$REPO/archive/refs/heads/main.tar.gz" 2>/dev/null || report_error "Wget download failed"
        tar -xzf main.tar.gz 2>/dev/null || report_error "Tar extraction failed"
        rm main.tar.gz 2>/dev/null
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
mkdir -p "$ICON_DIR" 2>/dev/null
cp package/contents/ui/images/lolzteam.png "$ICON_DIR/lztbalance.png" 2>/dev/null

$TOOL -t Plasma/Applet -u package/ >/dev/null 2>&1 || $TOOL -t Plasma/Applet -i package/ >/dev/null 2>&1 || report_error "kpackagetool install failed"

if command -v kbuildsycoca6 &>/dev/null; then
    kbuildsycoca6 2>/dev/null
elif command -v kbuildsycoca5 &>/dev/null; then
    kbuildsycoca5 2>/dev/null
fi

rm -rf "$INSTALL_DIR" 2>/dev/null
echo "Successfully Installed ^.^"
restart_plasma
