#!/usr/bin/env bash
# Removal of everything setup.sh installs.
#
# It lists what would go first and acts only after an explicit confirmation.
# Personal data is left alone: ROMs, saves, installed games and credentials
# stay where they are.

set -Eeuo pipefail

HANDHELD_KIT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export HANDHELD_KIT_ROOT
export DRY_RUN=0
export LOG_FILE="$HOME/steamos-handheld-kit-teardown.log"
RESULTS_FILE="$(mktemp -t steamos-handheld-teardown-results.XXXXXX)"
export RESULTS_FILE

. "$HANDHELD_KIT_ROOT/lib/common.sh"

CONFIRMED=0
LIST_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --confirm)  CONFIRMED=1; shift ;;
        --list)     LIST_ONLY=1; shift ;;
        -h|--help)
            cat <<'END'
Remove the configuration installed by setup.sh

  --list      list what would be removed, removing nothing
  --confirm   go ahead with the removal
  -h, --help  this message

With no arguments it behaves like --list.
END
            exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
done

FLATPAK_APPS=(
    com.github.tchx84.Flatseal
    io.github.kolunmi.Bazaar
    com.vysp3r.ProtonPlus
    com.heroicgameslauncher.hgl
    net.lutris.Lutris
    com.github.zocker_160.SyncThingy
    com.microsoft.Edge
    com.google.Chrome
    dev.lizardbyte.app.Sunshine
)
SUNSHINE=dev.lizardbyte.app.Sunshine

printf '\n%sThe following will be removed:%s\n\n' "$C_BOLD" "$C_RESET"

for app in "${FLATPAK_APPS[@]}"; do
    flatpak_has "$app" && printf '  Flatpak application    %s\n' "$app"
done
[ -d "$DECKY_DIR" ]                                   && printf '  Decky Loader + plugins %s\n' "$DECKY_DIR"

proton_builds=""
for candidate in "$COMPAT_DIR"/GE-Proton*; do
    [ -d "$candidate" ] && proton_builds="$proton_builds $(basename "$candidate")"
done
[ -n "$proton_builds" ]                               && printf '  Proton-GE             %s\n' "$proton_builds"

[ -d "$VENV_DIR" ]                                    && printf '  Python virtual env     %s\n' "$VENV_DIR"
[ -f "$HOME/Applications/EmuDeck.AppImage" ]          && printf '  EmuDeck                ~/Applications/EmuDeck.AppImage\n'
[ -d "$HOME/Applications/GeForceNOW_Setup" ]          && printf '  GeForce NOW installer  ~/Applications/GeForceNOW_Setup\n'
[ -f "$HOME/.local/share/applications/xbox-cloud-gaming.desktop" ] && printf '  menu entry             Xbox Cloud Gaming\n'
[ -f "$HOME/.local/share/applications/emudeck.desktop" ]           && printf '  menu entry             EmuDeck\n'

printf '\n%sThis will NOT be touched:%s\n\n' "$C_BOLD" "$C_RESET"
printf '  the ROMs on the memory card (%s)\n' "${SD_MOUNT:-none mounted}"
printf '  installed games, saves and credentials\n'
printf '  entries already added to the Steam library (remove those from Steam)\n'
printf "  Steam's configuration: the backups stay next to the originals\n"
printf '  the log files in your home directory\n\n'

if [ "$LIST_ONLY" = "1" ] || [ "$CONFIRMED" != "1" ]; then
    printf 'Nothing was changed. To go ahead: %s./teardown.sh --confirm%s\n\n' "$C_BOLD" "$C_RESET"
    exit 0
fi

# A second confirmation, typed, when there is a terminal to type into. Without
# one --confirm is the whole of the go-ahead: it cannot have been passed by
# accident, and the graphical launcher asks its own question before using it.
if [ -t 0 ]; then
    printf '%sConfirmation required.%s Type REMOVE to go ahead: ' "$C_YELLOW" "$C_RESET"
    read -r answer
    if [ "$answer" != "REMOVE" ]; then
        printf 'Cancelled: nothing was changed.\n\n'
        exit 0
    fi
fi

sudo_begin
trap 'sudo_end; rm -f "${RESULTS_FILE:-}"' EXIT

log_step "Remote access"
if flatpak_has "$SUNSHINE"; then
    # The service has to stop before the package goes, and the udev rules have
    # to go through the inverse script the package itself ships: deleting the
    # Flatpak alone would leave the rule behind in /etc/udev/rules.d.
    run "stopping the Sunshine service" \
        systemctl --user disable --now app-dev.lizardbyte.app.Sunshine.service || true
    run "removing Sunshine's system rules" \
        flatpak run --command=remove-additional-install.sh "$SUNSHINE" || \
        log_warn "removing the rules failed: check /etc/udev/rules.d/60-sunshine.rules"
fi

log_step "Flatpak applications"
for app in "${FLATPAK_APPS[@]}"; do
    if flatpak_has "$app"; then
        # The scope has to match where the application really lives: some may
        # have been installed per user as a fallback.
        scope=--system
        flatpak info --user "$app" >/dev/null 2>&1 && scope=--user
        run "removing $app ($scope)" \
            flatpak uninstall "$scope" --noninteractive --assumeyes "$app" \
            && record "$app" REMOVED "$scope" || record "$app" FAILED ""
    fi
done

log_step "Decky Loader"
if [ -d "$DECKY_DIR" ]; then
    run "stopping the plugin_loader service" sudo systemctl disable --now plugin_loader || true
    run "removing the service unit" sudo rm -f /etc/systemd/system/plugin_loader.service || true
    run "reloading systemd" sudo systemctl daemon-reload || true
    run "removing $DECKY_DIR" sudo rm -rf "$DECKY_DIR" \
        && record "Decky Loader" REMOVED "" || record "Decky Loader" FAILED ""
fi

log_step "Proton-GE"
if [ -d "$COMPAT_DIR" ]; then
    for d in "$COMPAT_DIR"/GE-Proton*; do
        [ -d "$d" ] || continue
        run "removing $(basename "$d")" rm -rf "$d" \
            && record "$(basename "$d")" REMOVED "" || record "$(basename "$d")" FAILED ""
    done
fi

log_step "Python virtual environment"
if [ -d "$VENV_DIR" ]; then
    run "removing $VENV_DIR" rm -rf "$VENV_DIR" \
        && record "Virtual environment" REMOVED "" || record "Virtual environment" FAILED ""
fi

log_step "Applications and menu entries"
for f in "$HOME/Applications/EmuDeck.AppImage" \
         "$HOME/Applications/.emudeck-version" \
         "$HOME/.local/share/applications/xbox-cloud-gaming.desktop" \
         "$HOME/.local/share/applications/emudeck.desktop"; do
    [ -e "$f" ] && { rm -f "$f" && log_ok "removed $f"; }
done
[ -d "$HOME/Applications/GeForceNOW_Setup" ] && \
    { rm -rf "$HOME/Applications/GeForceNOW_Setup" && log_ok "removed the GeForce NOW installer"; }
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

printf '\n%sRemoval complete.%s\n' "$C_GREEN" "$C_RESET"
printf 'The Xbox Cloud Gaming and GeForce NOW entries stay in the Steam library:\n'
printf 'remove them from there, with Steam open.\n\n'
