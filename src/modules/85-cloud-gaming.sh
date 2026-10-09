#!/usr/bin/env bash
# Cloud gaming: GeForce NOW and Xbox Cloud Gaming.
#
# The two services take different routes for a precise reason. NVIDIA publishes
# an installer for SteamOS that adds its own entry to Steam, applies the
# official artwork and sets the controller profile: using it beats reproducing
# its work. Xbox Cloud Gaming has no Linux client at all, so it goes through a
# browser in kiosk mode, wrapped in a menu entry that carries the launch
# arguments.

set -Eeuo pipefail
HANDHELD_KIT_ROOT="${HANDHELD_KIT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$HANDHELD_KIT_ROOT/lib/common.sh"

status=0
GFN_URL="https://download.nvidia.com/gfnpc/GeForceNOW_Setup.zip"
GFN_DIR="$HOME/Applications/GeForceNOW_Setup"
XBOX_URL="https://www.xbox.com/play"

graphics_available() { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }

# The real effect of NVIDIA's installer: the entry it adds to the library.
gfn_in_library() { grep -qa 'GeForce NOW' "$STEAM_ROOT"/userdata/*/config/shortcuts.vdf 2>/dev/null; }

# ===========================================================================
# Xbox Cloud Gaming
# ===========================================================================
log_step "Microsoft Edge"
flatpak_install com.microsoft.Edge "Microsoft Edge" || status=1

if flatpak_has com.microsoft.Edge; then
    # The browser's Gamepad API reads device metadata from /run/udev. Without
    # that access the game streams and the controller stays inert: a failure
    # that looks like the service's and belongs to the sandbox.
    if run "access to input devices for Edge" \
        flatpak override --user --filesystem=/run/udev:ro com.microsoft.Edge; then
        record "Edge permissions" INSTALLED "/run/udev read-only"
    else
        record "Edge permissions" FAILED "grant failed"
        status=1
    fi
fi

log_step "Xbox Cloud Gaming entry"
desktop="$HOME/.local/share/applications/xbox-cloud-gaming.desktop"

if [ "$DRY_RUN" = "1" ]; then
    printf '  %s[dry run]%s would create %s\n' "$C_YELLOW" "$C_RESET" "$desktop"
    record "Xbox Cloud Gaming" PLANNED "menu entry"
else
    mkdir -p "$(dirname "$desktop")"
    cat > "$desktop" <<END
[Desktop Entry]
Type=Application
Name=Xbox Cloud Gaming
Comment=Xbox Game Pass streaming
Exec=flatpak run com.microsoft.Edge --window-size=1280,800 --force-device-scale-factor=1.25 --device-scale-factor=1.25 --kiosk "$XBOX_URL"
Icon=applications-games
Terminal=false
Categories=Game;
StartupNotify=false
END
    chmod +x "$desktop"
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    log_ok "entry created: $desktop"
    record "Xbox Cloud Gaming" INSTALLED "menu entry ready"
fi

# ===========================================================================
# GeForce NOW
# ===========================================================================
log_step "GeForce NOW"

# Chrome is the browser GeForce NOW requires. Installing it first means the
# NVIDIA installer finds it already there and does not have to fetch it.
flatpak_install com.google.Chrome "Google Chrome" || status=1

if flatpak_has com.google.Chrome; then
    run "access to input devices for Chrome" \
        flatpak override --user --filesystem=/run/udev:ro com.google.Chrome \
        || log_warn "the grant for Chrome failed"
fi

# Already in the library: running the installer again would only bring its
# consent dialog back.
if gfn_in_library; then
    log_ok "GeForce NOW already in the Steam library"
    record "GeForce NOW" PRESENT "Steam library entry"
    exit "$status"
fi

if [ "$DRY_RUN" = "1" ]; then
    printf '  %s[dry run]%s would download and run the NVIDIA installer\n' "$C_YELLOW" "$C_RESET"
    record "GeForce NOW" PLANNED "NVIDIA's SteamOS installer"
    exit 0
fi

# --- Prerequisites the installer itself demands -----------------------------
# These belong to NVIDIA's installer, not to this tool: where they are absent
# the step is reported as one for the user to take, not as a failure.
missing=()
have steamos-add-to-steam || missing+=("steamos-add-to-steam")
uname -r | grep -qi valve || missing+=("the Valve kernel")
[ -d "$STEAM_ROOT/userdata" ] || missing+=("Steam user data")

if [ "${#missing[@]}" -gt 0 ]; then
    log_warn "the NVIDIA installer cannot run here: ${missing[*]} not found"
    log_warn "GeForce NOW can still be played in a browser at https://play.geforcenow.com"
    record "GeForce NOW" MANUAL "installer prerequisites absent: ${missing[*]}"
    exit "$status"
fi

# The controller profile directory has to exist before the installer runs: its
# own compatibility check requires it and it does not create it.
controller_config="$STEAM_ROOT/steamapps/common/Steam Controller Configs"
if [ ! -d "$controller_config" ]; then
    log_info "creating the controller profile directory the installer requires"
    mkdir -p "$controller_config"
fi

# --- Download and extract ---------------------------------------------------
if [ -x "$GFN_DIR/bin/GeForceNOW_Setup_Helper" ]; then
    log_ok "the NVIDIA installer is already present in $GFN_DIR"
else
    archive="$(mktemp)"
    trap 'rm -f "$archive"' EXIT
    if ! download_verified "$GFN_URL" "$archive" ""; then
        record "GeForce NOW" FAILED "download failed"
        exit 1
    fi
    mkdir -p "$HOME/Applications"
    if unzip -q -o "$archive" -d "$HOME/Applications"; then
        log_ok "installer extracted into $GFN_DIR"
        chmod +x "$GFN_DIR/GeForceNOW_Setup" 2>/dev/null || true
    else
        log_err "extracting the installer failed"
        record "GeForce NOW" FAILED "archive not extractable"
        rm -f "$archive"
        exit 1
    fi
    rm -f "$archive"
fi

# --- Run --------------------------------------------------------------------
# The installer asks for the user's consent in a dialog before doing anything,
# and it installs proprietary third-party software. With no graphical session
# that dialog cannot be drawn, and the installer exits 0 having installed
# nothing: it is therefore only run where the dialog can really appear.
if graphics_available; then
    log_info "starting the NVIDIA installer: a consent dialog will appear"
    log_info "answer yes to complete the installation"
    if ( cd "$GFN_DIR" && python3 ./bin/GeForceNOW_Setup_Helper ); then
        # Exit status 0 does not prove the user consented: the real effect is
        # checked instead, which is the entry appearing in the library.
        if gfn_in_library; then
            log_ok "GeForce NOW added to the Steam library"
            record "GeForce NOW" INSTALLED "Steam entry with NVIDIA artwork"
        else
            log_warn "the installer finished without adding the entry: consent was probably declined"
            record "GeForce NOW" MANUAL "run $GFN_DIR/GeForceNOW_Setup again and accept"
        fi
    else
        log_err "the NVIDIA installer ended with an error"
        record "GeForce NOW" FAILED "installer errored"
        status=1
    fi
else
    log_warn "no graphical session: the NVIDIA installer needs to draw a consent dialog"
    record "GeForce NOW" MANUAL "run $GFN_DIR/GeForceNOW_Setup from the desktop"
fi

exit "$status"
