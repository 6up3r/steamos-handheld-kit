#!/usr/bin/env bash
# EmuDeck, and where ROM libraries go.
#
# On SteamOS the official installer detects the immutable root filesystem and
# skips the dependency stage that would otherwise reach for pacman, so what it
# does reduces to: create ~/Applications, download the AppImage, make it
# executable and launch it.
#
# The first three steps happen here. Launching stays with the user: the
# AppImage opens a configuration interface and waits for human choices - which
# emulators, where the ROMs live - so in an unattended installer it would block
# indefinitely.

set -Eeuo pipefail
HANDHELD_KIT_ROOT="${HANDHELD_KIT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$HANDHELD_KIT_ROOT/lib/common.sh"

status=0
EMUDECK_API="https://api.github.com/repos/EmuDeck/emudeck-electron/releases/latest"
APPIMAGE="$HOME/Applications/EmuDeck.AppImage"
MARKER="$HOME/Applications/.emudeck-version"

# ---------------------------------------------------------------------------
# Where the ROMs go
# ---------------------------------------------------------------------------
log_step "ROM location"

if sd_mounted; then
    free="$(df -BG --output=avail "$SD_MOUNT" 2>/dev/null | tail -1 | tr -dc '0-9')"
    log_ok "memory card mounted at $SD_MOUNT (${free:-?}GB free)"
    if run "creating the Emulation folder on the memory card" mkdir -p "$SD_MOUNT/Emulation"; then
        record "ROM folder" INSTALLED "$SD_MOUNT/Emulation"
    else
        record "ROM folder" FAILED "$SD_MOUNT is not writable"
        status=1
    fi
    destination="$SD_MOUNT"
else
    log_warn "no memory card mounted: EmuDeck will have to be pointed at the internal drive"
    record "ROM folder" SKIPPED "no memory card"
    destination="$HOME"
fi

# ---------------------------------------------------------------------------
# EmuDeck
# ---------------------------------------------------------------------------
log_step "EmuDeck"

if [ "$DRY_RUN" = "1" ]; then
    printf '  %s[dry run]%s would download the latest EmuDeck AppImage to %s\n' \
        "$C_YELLOW" "$C_RESET" "$APPIMAGE"
    record "EmuDeck" PLANNED "latest AppImage and a menu entry"
    exit 0
fi

metadata="${TMPDIR:-/tmp}/emudeck-release.json"
trap 'rm -f "$metadata"' EXIT
if ! curl -fsSL -m 60 "$EMUDECK_API" -o "$metadata"; then
    log_err "the EmuDeck releases cannot be queried"
    record "EmuDeck" FAILED "GitHub API unreachable"
    exit 1
fi

mapfile -t fields < <(python3 - "$metadata" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
url = ''
for asset in data.get('assets', []):
    if asset['name'].endswith('.AppImage'):
        url = asset['browser_download_url']
        break
print(data.get('tag_name', ''))
print(url)
PY
)
tag="${fields[0]:-}"
appimage_url="${fields[1]:-}"

if [ -z "$appimage_url" ]; then
    log_err "no AppImage in the latest release"
    record "EmuDeck" FAILED "AppImage asset absent"
    exit 1
fi

if [ -f "$APPIMAGE" ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$tag" ]; then
    log_ok "already at version $tag"
    record "EmuDeck" PRESENT "$tag"
else
    mkdir -p "$HOME/Applications"
    log_info "downloading EmuDeck $tag"
    if curl -fL --retry 3 --retry-delay 2 -m 900 "$appimage_url" -o "$APPIMAGE.partial"; then
        mv "$APPIMAGE.partial" "$APPIMAGE"
        chmod +x "$APPIMAGE"
        echo "$tag" > "$MARKER"
        log_ok "EmuDeck $tag installed at $APPIMAGE"
        record "EmuDeck" INSTALLED "$tag"
    else
        rm -f "$APPIMAGE.partial"
        log_err "download failed"
        record "EmuDeck" FAILED "download failed"
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Application menu entry
# ---------------------------------------------------------------------------
log_step "Menu entry"
desktop="$HOME/.local/share/applications/emudeck.desktop"
mkdir -p "$(dirname "$desktop")"
cat > "$desktop" <<END
[Desktop Entry]
Type=Application
Name=EmuDeck
Comment=Set up emulators and ROM folders
Exec=$APPIMAGE
Icon=applications-games
Terminal=false
Categories=Game;
END
chmod +x "$desktop"
log_ok "menu entry created"

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

record "EmuDeck configuration" MANUAL "start EmuDeck and point it at $destination"

log_warn "EmuDeck is installed but not configured yet."
log_warn "Start it from the application menu and, when asked where ROMs go, choose: $destination"

exit "$status"
