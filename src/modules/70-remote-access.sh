#!/usr/bin/env bash
# Remote access: Sunshine as a streaming server on the handheld.
#
# The handheld acts as the server and is driven from another computer with a
# Moonlight client. Compared with Steam's own remote play the stream is steadier
# and lower latency, and it does not depend on the Steam client being open.
#
# The Flatpak package carries two scripts that have to be run separately:
# additional-install.sh installs the udev rule for /dev/uinput - without which
# the client cannot move the mouse or a gamepad - and registers the service;
# remove-additional-install.sh undoes both, and is what teardown.sh runs.

set -Eeuo pipefail
HANDHELD_KIT_ROOT="${HANDHELD_KIT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$HANDHELD_KIT_ROOT/lib/common.sh"

status=0
SUNSHINE=dev.lizardbyte.app.Sunshine

log_step "Sunshine"
flatpak_install "$SUNSHINE" "Sunshine" || status=1

if ! flatpak_has "$SUNSHINE"; then
    exit "$status"
fi

# ---------------------------------------------------------------------------
# Complementary install: udev rule and service
# ---------------------------------------------------------------------------
log_step "System rules for remote control"

if [ "$DRY_RUN" = "1" ]; then
    printf '  %s[dry run]%s would run additional-install.sh and enable the service\n' \
        "$C_YELLOW" "$C_RESET"
    exit 0
fi

# The script is idempotent: running it again on a prepared system duplicates
# nothing.
if run_visible "installing the udev rule and the service" \
    flatpak run --command=additional-install.sh "$SUNSHINE"; then
    log_ok "system components installed"
    record "Sunshine udev rule" INSTALLED "/dev/uinput reachable"
else
    log_warn "the complementary install failed: remote control of the mouse and"
    log_warn "gamepad may not work"
    record "Sunshine udev rule" FAILED "additional-install.sh errored"
    status=1
fi

# What matters is that Sunshine can write to /dev/uinput to synthesise the
# mouse and gamepad events the client sends. The udev rule just installed
# carries TAG+="uaccess", which hands the device to the user of the active
# session through an ACL: no group to join, no reboot to wait for. So the real
# capability is tested, not an indirect sign of it.
if [ -w /dev/uinput ]; then
    log_ok "/dev/uinput is writable: remote mouse and gamepad control is enabled"
    record "uinput access" VERIFIED "ACL granted by the udev rule"
else
    log_warn "/dev/uinput is not writable by this user"
    log_warn "the ACL is granted to the active session: check again after the next sign-in"
    record "uinput access" MANUAL "restart the handheld and re-check with ./setup.sh --verify"
fi

# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------
log_step "Sunshine service"

# The Flatpak package registers the unit under its full name, not under a
# generic "sunshine.service".
UNIT="app-dev.lizardbyte.app.Sunshine.service"

if systemctl --user list-unit-files 2>/dev/null | grep -q "^${UNIT}"; then
    if run "enabling and starting the service" systemctl --user enable --now "$UNIT"; then
        sleep 5
        if systemctl --user is-active --quiet "$UNIT"; then
            log_ok "service active, it will start at every sign-in"
            record "Sunshine service" INSTALLED "$UNIT"
        else
            log_warn "service enabled but not active yet"
            systemctl --user status "$UNIT" --no-pager -n 5 2>&1 | tail -6 | sed 's/^/    /'
            record "Sunshine service" FAILED "not active after starting"
            status=1
        fi
    else
        record "Sunshine service" FAILED "enabling failed"
        status=1
    fi
else
    log_warn "unit $UNIT is not registered: start Sunshine from the application menu"
    record "Sunshine service" MANUAL "start Sunshine from the application menu"
fi

# ---------------------------------------------------------------------------
# Where to connect
# ---------------------------------------------------------------------------
log_step "How to connect"
address="$(ip -4 -br addr show 2>/dev/null | grep -v '^lo' | awk '{print $3}' | cut -d/ -f1 | head -1)"
log_info "web interface: https://${address:-<this-device-address>}:47990"
log_info "from Moonlight on your computer: add the host ${address:-<this-device-address>} and confirm the PIN"

record "Sunshine configuration" MANUAL \
    "open https://${address:-<this-device-address>}:47990, set a username and password, then pair Moonlight"

exit "$status"
