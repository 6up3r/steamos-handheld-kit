#!/usr/bin/env bash
# Flatpak groundwork: the Flathub remote, an update pass, permissions manager
# and store.
#
# Flatpak is the only installation route that survives a SteamOS update,
# because it lives in /var rather than in the immutable root filesystem.

set -Eeuo pipefail
HANDHELD_KIT_ROOT="${HANDHELD_KIT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$HANDHELD_KIT_ROOT/lib/common.sh"

status=0

# --- The Flathub remote -----------------------------------------------------
log_step "Flathub remote"
if flatpak remotes --columns=name 2>/dev/null | grep -qx flathub; then
    log_ok "Flathub already configured"
    record "Flathub remote" PRESENT ""
else
    if run "adding Flathub" flatpak remote-add --if-not-exists --system \
        flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
        record "Flathub remote" INSTALLED ""
    else
        record "Flathub remote" FAILED ""
        status=1
    fi
fi

# --- Application index ------------------------------------------------------
# Without this step "flatpak search" finds nothing on a freshly installed
# system: the index has not been downloaded yet.
log_step "Application index"
run "refreshing the Flathub index" flatpak update --appstream --system --noninteractive \
    && log_ok_done "index refreshed" \
    || log_warn "refreshing the index failed: continuing"

# --- Update what is already installed ---------------------------------------
log_step "Updating existing applications"
if [ "$(flatpak list --app --columns=application 2>/dev/null | wc -l)" -gt 0 ]; then
    run "updating applications" flatpak update --system --noninteractive --assumeyes \
        && log_ok_done "applications updated" \
        || log_warn "the update partially failed"
else
    log_info "no Flatpak application installed yet"
fi

# --- Base applications ------------------------------------------------------
log_step "Base applications"

# Flatseal: without it the other applications cannot see ~/.steam or the
# memory card, and the permissions below have no user-facing way to be undone.
flatpak_install com.github.tchx84.Flatseal "Flatseal" || status=1

# Bazaar: a store that can be driven with a gamepad, which suits a handheld
# better than a desktop-oriented software centre.
flatpak_install io.github.kolunmi.Bazaar "Bazaar" || status=1

exit "$status"
