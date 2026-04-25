#!/bin/bash
set -e

TOOL=""
if command -v kpackagetool6 &>/dev/null; then
    TOOL="kpackagetool6"
elif command -v kpackagetool5 &>/dev/null; then
    TOOL="kpackagetool5"
else
    echo "Error: kpackagetool not found. Install plasma-framework."
    exit 1
fi

$TOOL -t Plasma/Applet -u package/ 2>/dev/null || $TOOL -t Plasma/Applet -i package/

if command -v kbuildsycoca6 &>/dev/null; then
    kbuildsycoca6 2>/dev/null
elif command -v kbuildsycoca5 &>/dev/null; then
    kbuildsycoca5 2>/dev/null
fi

echo "Installed. Restart Plasma to apply:"
echo "  kquitapp6 plasmashell && kstart plasmashell"
