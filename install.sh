#!/bin/bash
set -e

REPO="9sx77ssl/lzt-plasma"
INSTALL_DIR="$HOME/.lzt-plasma-install"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -d "$SCRIPT_DIR/.git" ] && [ "$(cd "$SCRIPT_DIR" && git remote get-url origin 2>/dev/null)" = "https://github.com/$REPO.git" ]; then
    cd "$SCRIPT_DIR"
    git pull --depth 1
else
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    if command -v git &>/dev/null; then
        if [ -d "lzt-plasma/.git" ]; then
            cd lzt-plasma
            git pull --depth 1
        else
            rm -rf lzt-plasma
            git clone --depth 1 "https://github.com/$REPO.git" lzt-plasma
            cd lzt-plasma
        fi
    elif command -v curl &>/dev/null; then
        curl -sSLO "https://github.com/$REPO/archive/refs/heads/main.tar.gz"
        tar -xzf main.tar.gz
        rm main.tar.gz
        cd lzt-plasma-main
    elif command -v wget &>/dev/null; then
        wget -q "https://github.com/$REPO/archive/refs/heads/main.tar.gz"
        tar -xzf main.tar.gz
        rm main.tar.gz
        cd lzt-plasma-main
    else
        echo "Error: git, curl, or wget required"
        exit 1
    fi
fi

TOOL=""
if command -v kpackagetool6 &>/dev/null; then
    TOOL="kpackagetool6"
elif command -v kpackagetool5 &>/dev/null; then
    TOOL="kpackagetool5"
else
    echo "kpackagetool not found. Install plasma-framework."
    exit 1
fi

ICON_DIR="$HOME/.local/share/icons/hicolor/64x64/apps"
mkdir -p "$ICON_DIR"
cp package/contents/ui/images/lolzteam.png "$ICON_DIR/lztbalance.png"

$TOOL -t Plasma/Applet -u package/ 2>/dev/null || $TOOL -t Plasma/Applet -i package/

if command -v kbuildsycoca6 &>/dev/null; then
    kbuildsycoca6 2>/dev/null
elif command -v kbuildsycoca5 &>/dev/null; then
    kbuildsycoca5 2>/dev/null
fi

rm -rf "$INSTALL_DIR"
echo "Installed. Restart Plasma:"
echo "  kquitapp6 plasmashell && kstart plasmashell"
