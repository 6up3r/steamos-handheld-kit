#!/usr/bin/env bash
# The two non-Steam game launchers.
#
# Heroic covers the storefronts - Epic, GOG and Amazon - in one client built
# for exactly that. Lutris covers what has no storefront behind it: standalone
# Windows installers, older games, and the collection of runners and community
# install scripts that go with them. They overlap very little in practice.

set -Eeuo pipefail
HANDHELD_KIT_ROOT="${HANDHELD_KIT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$HANDHELD_KIT_ROOT/lib/common.sh"

status=0

# Both launchers need the same two things, and for the same reasons: Steam's
# compatibility tools, without which their list of Proton builds stays empty,
# and the memory card, without which games cannot be installed there.
grant_launcher_access() {
    local appid="$1" name="$2" granted="Steam compatibility tools"

    if ! run "$name: access to Steam's compatibility tools" \
        flatpak override --user --filesystem="$HOME/.steam" "$appid"; then
        log_warn "$name: the grant failed"
        return 1
    fi

    if sd_mounted; then
        if run "$name: access to the memory card" \
            flatpak override --user --filesystem="$SD_MOUNT" "$appid"; then
            granted="$granted and the memory card"
        else
            log_warn "$name: the memory card grant failed"
        fi
    fi

    record "$name permissions" INSTALLED "$granted"
    return 0
}

log_step "Heroic Games Launcher"
flatpak_install com.heroicgameslauncher.hgl "Heroic Games Launcher" || status=1
if flatpak_has com.heroicgameslauncher.hgl; then
    grant_launcher_access com.heroicgameslauncher.hgl "Heroic" || status=1
fi

log_step "Lutris"
flatpak_install net.lutris.Lutris "Lutris" || status=1
if flatpak_has net.lutris.Lutris; then
    grant_launcher_access net.lutris.Lutris "Lutris" || status=1
fi

record "Store sign-in" MANUAL "sign in to Epic and GOG inside Heroic, and to any store you use inside Lutris"

exit "$status"
