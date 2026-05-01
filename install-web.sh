#!/bin/bash
set -e

REPO="9sx77ssl/lzt-plasma"
INSTALL_DIR="$HOME/.lzt-plasma-install"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if command -v git &>/dev/null; then
    rm -rf lzt-plasma
    git clone --depth 1 "https://github.com/$REPO.git" lzt-plasma
    cd lzt-plasma
else
    if command -v curl &>/dev/null; then
        curl -sSLO "https://github.com/$REPO/archive/refs/heads/main.zip"
        unzip -q main.zip
        rm main.zip
        cd lzt-plasma-main
    elif command -v wget &>/dev/null; then
        wget -q "https://github.com/$REPO/archive/refs/heads/main.zip"
        unzip -q main.zip
        rm main.zip
        cd lzt-plasma-main
    else
        echo "Error: git, curl, or wget required"
        exit 1
    fi
fi

chmod +x install.sh
./install.sh
rm -rf "$INSTALL_DIR"
