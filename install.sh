#!/usr/bin/env bash
# LZT Plasmoid installer — Plasma 6 (KF6).
# Pulls the latest version and installs/upgrades the widget. Works on Arch,
# Debian/Ubuntu, Fedora, openSUSE, Gentoo, RHEL and their derivatives.

set -u
set -o pipefail

REPO="9sx77ssl/lzt-plasma"
INSTALL_DIR="$HOME/.lzt-plasma-install"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ERROR_LOG="/tmp/lzt-plasma-install-error.log"
APPLET_ID="org.kde.plasma.lztbalance"

if [ -t 1 ]; then
    C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_ERR=$'\e[31m'; C_DIM=$'\e[2m'; C_RST=$'\e[0m'
else
    C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_RST=""
fi
say()  { printf '%s» %s\n' "${C_DIM}" "$*${C_RST}"; }
ok()   { printf '%s✓%s %s\n' "${C_OK}" "${C_RST}" "$*"; }
warn() { printf '%s!%s %s\n' "${C_WARN}" "${C_RST}" "$*" >&2; }
die()  { printf '%s✗%s %s\n   see %s\n' "${C_ERR}" "${C_RST}" "$*" "$ERROR_LOG" >&2
         rm -rf "$INSTALL_DIR" 2>/dev/null; exit 1; }
run_quiet() { "$@" >>"$ERROR_LOG" 2>&1; }

detect_distro() {
    [ -r /etc/os-release ] || { echo unknown; return; }
    . /etc/os-release
    case " $ID ${ID_LIKE:-} " in
        *" arch "*|*" archlinux "*) echo arch ;;
        *" debian "*|*" ubuntu "*)  echo debian ;;
        *" fedora "*)               echo fedora ;;
        *" rhel "*|*" centos "*)    echo rhel ;;
        *" suse "*|*" opensuse "*)  echo suse ;;
        *" gentoo "*)               echo gentoo ;;
        *) case "$ID" in
               arch|artix|manjaro|endeavouros|garuda|cachyos) echo arch ;;
               debian|ubuntu|linuxmint|pop|kdeneon|kali|elementary) echo debian ;;
               fedora|nobara) echo fedora ;;
               rhel|centos|rocky|almalinux|ol) echo rhel ;;
               opensuse*|sles|suse) echo suse ;;
               gentoo) echo gentoo ;;
               *) echo unknown ;;
           esac ;;
    esac
}

ensure_deps() {
    local distro="$1"
    say "Distro: ${distro}"
    if command -v kpackagetool6 >/dev/null 2>&1; then
        ok "Plasma 6 tools present"
        return 0
    fi
    say "Installing Plasma 6 / KF6 dependencies (may prompt for sudo)…"
    case "$distro" in
        arch)   run_quiet sudo pacman -Sy --needed --noconfirm plasma-framework git curl wget ;;
        debian) run_quiet sudo apt-get update
                run_quiet sudo apt-get install -y plasma-framework git curl wget \
                  || run_quiet sudo apt-get install -y kf6-plasma-framework git curl wget ;;
        fedora) run_quiet sudo dnf install -y kf6-plasma-framework git curl wget \
                  || run_quiet sudo dnf install -y plasma-framework git curl wget ;;
        rhel)   run_quiet sudo dnf install -y kf6-plasma-framework git curl wget ;;
        suse)   run_quiet sudo zypper install -y plasma6-framework git curl wget \
                  || run_quiet sudo zypper install -y plasma-framework6 git curl wget ;;
        gentoo) run_quiet sudo emerge -q kde-frameworks/plasma-framework dev-vcs/git net-misc/curl net-misc/wget ;;
        *)      warn "Unknown distro — assuming Plasma 6 is already installed" ;;
    esac
}

# Always resolve to the latest source: pull if run from a clone, else clone fresh.
fetch_source() {
    if [ -d "$SCRIPT_DIR/.git" ] && [ -d "$SCRIPT_DIR/package" ] \
       && [[ "$(cd "$SCRIPT_DIR" && git remote get-url origin 2>/dev/null)" == *"$REPO"* ]]; then
        say "Local clone — pulling latest"
        ( cd "$SCRIPT_DIR" && run_quiet git pull --ff-only ) || warn "git pull failed, using local state"
        SOURCE_DIR="$SCRIPT_DIR"
        return 0
    fi

    mkdir -p "$INSTALL_DIR" || die "Cannot create $INSTALL_DIR"
    if command -v git >/dev/null 2>&1; then
        say "Cloning latest $REPO"
        rm -rf "$INSTALL_DIR/lzt-plasma"
        if run_quiet git clone --depth 1 "https://github.com/$REPO.git" "$INSTALL_DIR/lzt-plasma"; then
            SOURCE_DIR="$INSTALL_DIR/lzt-plasma"; return 0
        fi
    fi

    say "Falling back to tarball"
    local tar="$INSTALL_DIR/lzt-plasma.tar.gz"
    if command -v curl >/dev/null 2>&1; then
        run_quiet curl -sSL -o "$tar" "https://github.com/$REPO/archive/refs/heads/main.tar.gz" || die "download failed"
    elif command -v wget >/dev/null 2>&1; then
        run_quiet wget -q -O "$tar" "https://github.com/$REPO/archive/refs/heads/main.tar.gz" || die "download failed"
    else
        die "Need one of: git, curl, wget"
    fi
    run_quiet tar -xzf "$tar" -C "$INSTALL_DIR" || die "tar extraction failed"
    rm -f "$tar"
    SOURCE_DIR="$INSTALL_DIR/lzt-plasma-main"
    [ -d "$SOURCE_DIR" ] || die "extracted source dir missing"
}

install_plasmoid() {
    cd "$SOURCE_DIR" || die "cannot cd to $SOURCE_DIR"
    command -v kpackagetool6 >/dev/null 2>&1 || die "kpackagetool6 not found — install plasma-framework / kf6-plasma-framework"

    # Custom tab/widget icons into the user icon theme.
    local icon_dir="$HOME/.local/share/icons/hicolor/scalable/apps"
    mkdir -p "$icon_dir"
    cp -f package/contents/ui/images/lolzteam.svg   "$icon_dir/lztbalance.svg" 2>/dev/null || true
    cp -f package/contents/ui/images/help.svg       "$icon_dir/lzt-help.svg"   2>/dev/null || true
    cp -f package/contents/ui/images/crypto-tab.svg "$icon_dir/lzt-crypto.svg" 2>/dev/null || true

    if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -q "^${APPLET_ID}$"; then
        say "Upgrading widget"
        run_quiet kpackagetool6 -t Plasma/Applet -u package/ || die "upgrade failed"
    else
        say "Installing widget"
        run_quiet kpackagetool6 -t Plasma/Applet -i package/ || die "install failed"
    fi
    run_quiet kbuildsycoca6 || true
    ok "Installed at \$HOME/.local/share/plasma/plasmoids/${APPLET_ID}"
}

restart_plasma() {
    pgrep -x plasmashell >/dev/null 2>&1 || { say "plasmashell not running, skipping restart"; return 0; }
    say "Restarting plasmashell"
    if command -v kquitapp6 >/dev/null 2>&1 && command -v kstart >/dev/null 2>&1; then
        run_quiet kquitapp6 plasmashell
        sleep 1
        ( setsid kstart plasmashell >/dev/null 2>&1 & ) || true
    else
        ( setsid plasmashell --replace >/dev/null 2>&1 & ) || true
    fi
    ok "plasmashell restarted"
}

: > "$ERROR_LOG"
ensure_deps "$(detect_distro)"
fetch_source
install_plasmoid
restart_plasma
[ "${SOURCE_DIR:-}" = "$INSTALL_DIR/lzt-plasma" ] && rm -rf "$INSTALL_DIR"

printf '\n%sDone%s — right-click the panel → Add Widgets → search "LZT Plasmoid"\n' "${C_OK}" "${C_RST}"
