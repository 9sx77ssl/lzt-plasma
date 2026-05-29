#!/usr/bin/env bash
# LZT Market Balance — universal installer
# Supports Plasma 6 (KF6) on Arch, Debian, Ubuntu, Fedora, openSUSE, Gentoo,
# RHEL/Rocky/Alma, and any derivative thereof. Falls back gracefully when the
# package manager can't be detected.

set -u
set -o pipefail

REPO="9sx77ssl/lzt-plasma"
INSTALL_DIR="$HOME/.lzt-plasma-install"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ERROR_LOG="/tmp/lzt-plasma-install-error.log"
APPLET_ID="org.kde.plasma.lztbalance"

# ── colours / output ───────────────────────────────────────────────
if [ -t 1 ]; then
    C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_ERR=$'\e[31m'; C_DIM=$'\e[2m'; C_RST=$'\e[0m'
else
    C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_RST=""
fi
say()  { printf '%s%s%s\n' "${C_DIM}»${C_RST}" " " "$*"; }
ok()   { printf '%s✓%s %s\n' "${C_OK}" "${C_RST}" "$*"; }
warn() { printf '%s!%s %s\n' "${C_WARN}" "${C_RST}" "$*" >&2; }
die()  { printf '%s✗%s %s\n' "${C_ERR}" "${C_RST}" "$*" >&2
         printf '%s  see %s%s\n' "${C_DIM}" "$ERROR_LOG" "${C_RST}" >&2
         rm -rf "$INSTALL_DIR" 2>/dev/null
         exit 1; }

log_err() { echo "[$(date -Is)] $*" >> "$ERROR_LOG"; }

run_quiet() {
    # Run command, swallow output to ERROR_LOG, return its exit code
    "$@" >>"$ERROR_LOG" 2>&1
}

# ── distro detection ───────────────────────────────────────────────
detect_distro() {
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        case " $ID $ID_LIKE " in
            *" arch "*|*" archlinux "*)    echo "arch"   ;;
            *" debian "*|*" ubuntu "*)     echo "debian" ;;
            *" fedora "*)                  echo "fedora" ;;
            *" rhel "*|*" centos "*)       echo "rhel"   ;;
            *" suse "*|*" opensuse "*)     echo "suse"   ;;
            *" gentoo "*)                  echo "gentoo" ;;
            *)
                # try by ID alone
                case "$ID" in
                    arch|artix|manjaro|endeavouros|garuda|cachyos)  echo "arch"   ;;
                    debian|ubuntu|linuxmint|pop|kdeneon|kali|elementary) echo "debian" ;;
                    fedora|nobara)                                  echo "fedora" ;;
                    rhel|centos|rocky|almalinux|ol)                 echo "rhel"   ;;
                    opensuse*|sles|suse)                            echo "suse"   ;;
                    gentoo)                                         echo "gentoo" ;;
                    *)                                              echo "unknown" ;;
                esac
                ;;
        esac
    else
        echo "unknown"
    fi
}

# ── ensure dependencies (best-effort) ──────────────────────────────
ensure_deps() {
    local distro="$1"
    say "Distro detected: ${distro}"

    # If kpackagetool6 already exists, deps are satisfied
    if command -v kpackagetool6 >/dev/null 2>&1; then
        ok "kpackagetool6 found, skipping dependency install"
        return 0
    fi

    say "Installing Plasma 6 / KF6 dependencies (may prompt for sudo)…"

    case "$distro" in
        arch)
            run_quiet sudo pacman -Sy --needed --noconfirm plasma-framework git curl wget
            ;;
        debian)
            run_quiet sudo apt-get update
            # Plasma 6 packages in Debian/Ubuntu use kf6 prefix
            run_quiet sudo apt-get install -y plasma-framework git curl wget \
                || run_quiet sudo apt-get install -y kf6-plasma-framework git curl wget
            ;;
        fedora)
            run_quiet sudo dnf install -y kf6-plasma-framework git curl wget \
                || run_quiet sudo dnf install -y plasma-framework git curl wget
            ;;
        rhel)
            run_quiet sudo dnf install -y kf6-plasma-framework git curl wget
            ;;
        suse)
            run_quiet sudo zypper install -y plasma6-framework git curl wget \
                || run_quiet sudo zypper install -y plasma-framework6 git curl wget
            ;;
        gentoo)
            run_quiet sudo emerge -q kde-frameworks/plasma-framework dev-vcs/git net-misc/curl net-misc/wget
            ;;
        *)
            warn "Unknown distro — assuming Plasma 6 is already installed"
            ;;
    esac
}

# ── fetch source ───────────────────────────────────────────────────
fetch_source() {
    # If we're already running from inside a clone of this repo, just use it
    if [ -d "$SCRIPT_DIR/.git" ] && [ -d "$SCRIPT_DIR/package" ]; then
        local remote
        remote="$(cd "$SCRIPT_DIR" && git remote get-url origin 2>/dev/null || true)"
        if [[ "$remote" == *"$REPO"* ]]; then
            say "Running from local clone — pulling latest"
            ( cd "$SCRIPT_DIR" && run_quiet git pull --depth 1 ) || warn "git pull failed, using local state"
            SOURCE_DIR="$SCRIPT_DIR"
            return 0
        fi
    fi

    # Otherwise download fresh into INSTALL_DIR
    mkdir -p "$INSTALL_DIR" 2>/dev/null || die "Cannot create $INSTALL_DIR"

    if command -v git >/dev/null 2>&1; then
        say "Cloning $REPO"
        rm -rf "$INSTALL_DIR/lzt-plasma" 2>/dev/null
        if run_quiet git clone --depth 1 "https://github.com/$REPO.git" "$INSTALL_DIR/lzt-plasma"; then
            SOURCE_DIR="$INSTALL_DIR/lzt-plasma"
            return 0
        fi
    fi

    say "Falling back to tarball download"
    local tar="$INSTALL_DIR/lzt-plasma.tar.gz"
    if command -v curl >/dev/null 2>&1; then
        run_quiet curl -sSL -o "$tar" "https://github.com/$REPO/archive/refs/heads/main.tar.gz" || die "curl download failed"
    elif command -v wget >/dev/null 2>&1; then
        run_quiet wget -q -O "$tar" "https://github.com/$REPO/archive/refs/heads/main.tar.gz"   || die "wget download failed"
    else
        die "Need one of: git, curl, wget"
    fi

    run_quiet tar -xzf "$tar" -C "$INSTALL_DIR" || die "tar extraction failed"
    rm -f "$tar"

    SOURCE_DIR="$INSTALL_DIR/lzt-plasma-main"
    [ -d "$SOURCE_DIR" ] || die "Extracted source dir missing"
}

# ── install the plasmoid ───────────────────────────────────────────
install_plasmoid() {
    cd "$SOURCE_DIR" || die "Cannot cd to $SOURCE_DIR"

    if ! command -v kpackagetool6 >/dev/null 2>&1; then
        die "kpackagetool6 not found — install plasma-framework / kf6-plasma-framework for your distro and re-run"
    fi

    # Copy SVG to user icon theme so the widget icon resolves
    local icon_dir="$HOME/.local/share/icons/hicolor/scalable/apps"
    mkdir -p "$icon_dir" 2>/dev/null
    cp -f package/contents/ui/images/lolzteam.svg   "$icon_dir/lztbalance.svg" 2>/dev/null || true
    cp -f package/contents/ui/images/help.svg       "$icon_dir/lzt-help.svg"   2>/dev/null || true
    cp -f package/contents/ui/images/crypto-tab.svg "$icon_dir/lzt-crypto.svg" 2>/dev/null || true

    # Try upgrade first, fall back to install
    if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -q "^${APPLET_ID}$"; then
        say "Upgrading existing widget"
        if ! run_quiet kpackagetool6 -t Plasma/Applet -u package/; then
            die "kpackagetool6 upgrade failed"
        fi
    else
        say "Installing widget"
        if ! run_quiet kpackagetool6 -t Plasma/Applet -i package/; then
            die "kpackagetool6 install failed"
        fi
    fi

    # Rebuild KDE cache so the icon and widget show up immediately
    run_quiet kbuildsycoca6 || true

    ok "Widget installed at \$HOME/.local/share/plasma/plasmoids/${APPLET_ID}"
}

# ── restart plasmashell so the user sees the new version ───────────
restart_plasma() {
    if ! pgrep -x plasmashell >/dev/null 2>&1; then
        say "plasmashell not running, skipping restart"
        return 0
    fi
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

# ── main ───────────────────────────────────────────────────────────
: > "$ERROR_LOG"

DISTRO="$(detect_distro)"
ensure_deps "$DISTRO"
fetch_source
install_plasmoid
restart_plasma

# Clean up downloaded copy (keep local clone)
[ "${SOURCE_DIR:-}" = "$INSTALL_DIR/lzt-plasma" ] && rm -rf "$INSTALL_DIR"

printf '\n%sSuccessfully installed%s — right-click your panel → Add Widgets → search "LZT Market Balance"\n' "${C_OK}" "${C_RST}"
