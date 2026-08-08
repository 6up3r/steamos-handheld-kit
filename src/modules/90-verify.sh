#!/usr/bin/env bash
# Final verification.
#
# This does not re-read what the script believed it did: it interrogates the
# system. A step that printed "installed" and then produced nothing is caught
# here, because every entry is checked against the real artefact.

set -Eeuo pipefail
HANDHELD_KIT_ROOT="${HANDHELD_KIT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$HANDHELD_KIT_ROOT/lib/common.sh"

# In dry-run mode nothing has been changed: checking the state would measure
# the system as it was, and report as missing everything a real run would have
# installed.
if [ "$DRY_RUN" = "1" ]; then
    log_info "verification not run in dry-run mode: nothing has been changed"
    log_info "to check an already configured system: ./setup.sh --verify"
    exit 0
fi

ok=0
ko=0

# Always succeeds: it is the check that ran, not necessarily the thing checked
# that passed. A non-zero return here would end the script under set -e,
# stopping the verification at the first problem instead of listing them all.
inspect() {
    local description="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf '  %s[ok]%s      %s\n' "$C_GREEN" "$C_RESET" "$description"
        ok=$((ok + 1))
    else
        printf '  %s[missing]%s %s\n' "$C_RED" "$C_RESET" "$description"
        ko=$((ko + 1))
    fi
    return 0
}

# Same shape, for a check that is not a single command.
pass() { printf '  %s[ok]%s      %s\n' "$C_GREEN" "$C_RESET" "$1"; ok=$((ok + 1)); }
fail() { printf '  %s[missing]%s %s\n' "$C_RED" "$C_RESET" "$1"; ko=$((ko + 1)); }

log_step "Hardware enablement"
inspect "InputPlumber service active"     systemctl is-active --quiet inputplumber
inspect "virtual gamepad present"         grep -q 'X-Box 360 pad' /proc/bus/input/devices
inspect "power profiles readable"         test -r /sys/firmware/acpi/platform_profile
if [ -d /sys/class/firmware-attributes/asus-armoury/attributes/ppt_pl1_spl ] \
   || compgen -G "/sys/class/hwmon/*/power1_cap" >/dev/null 2>&1; then
    pass "TDP controls exposed"
else
    fail "TDP controls exposed"
fi

log_step "Flatpak applications"
for pair in \
    "com.github.tchx84.Flatseal|Flatseal" \
    "io.github.kolunmi.Bazaar|Bazaar" \
    "com.vysp3r.ProtonPlus|ProtonPlus" \
    "com.heroicgameslauncher.hgl|Heroic Games Launcher" \
    "net.lutris.Lutris|Lutris" \
    "com.github.zocker_160.SyncThingy|SyncThingy" \
    "com.microsoft.Edge|Microsoft Edge" \
    "com.google.Chrome|Google Chrome" ; do
    inspect "${pair#*|}" flatpak info "${pair%%|*}"
done

log_step "Sandbox permissions"
check_override() {
    local appid="$1" path="$2" label="$3"
    if flatpak info --show-permissions "$appid" 2>/dev/null | grep -q -- "$path"; then
        pass "$label"
    else
        fail "$label"
    fi
}
flatpak info com.microsoft.Edge >/dev/null 2>&1 && \
    check_override com.microsoft.Edge "/run/udev" "Edge reads input devices"
flatpak info com.heroicgameslauncher.hgl >/dev/null 2>&1 && \
    check_override com.heroicgameslauncher.hgl ".steam" "Heroic reaches the compatibility tools"
flatpak info net.lutris.Lutris >/dev/null 2>&1 && \
    check_override net.lutris.Lutris ".steam" "Lutris reaches the compatibility tools"

log_step "Decky"
inspect "plugin_loader service active" systemctl is-active --quiet plugin_loader
expected_plugins=("SteamGridDB" "ProtonDB Badges" "Decky Cloud Save" "CSS Loader" "Storage Cleaner" "Battery Tracker")
# HueSync is only installed where the hardware has RGB lights, so it is only
# expected here under the same condition.
if compgen -G "/sys/class/leds/*rgb*" >/dev/null 2>&1; then
    expected_plugins+=("HueSync")
fi
for plugin in "${expected_plugins[@]}"; do
    inspect "plugin $plugin" test -d "$DECKY_DIR/plugins/$plugin"
done

log_step "Proton"
proton_ge="$(latest_proton_ge)"
if [ -n "$proton_ge" ]; then
    pass "Proton-GE installed: $proton_ge"
    # Having the archive is not enough: what counts is that Steam uses it.
    if grep -qa "\"$proton_ge\"" "$STEAM_ROOT/config/config.vdf" 2>/dev/null; then
        pass "set as the global default"
    else
        fail "global default not set to $proton_ge"
    fi
else
    fail "no Proton-GE version installed"
fi

log_step "Emulation"
if sd_mounted; then
    pass "memory card mounted at $SD_MOUNT"
    inspect "Emulation folder on the card" test -d "$SD_MOUNT/Emulation"
else
    fail "memory card mounted"
fi
inspect "EmuDeck downloaded"          test -x "$HOME/Applications/EmuDeck.AppImage"

log_step "Remote access"
inspect "Sunshine installed"          flatpak info dev.lizardbyte.app.Sunshine
inspect "Sunshine service active"     systemctl --user is-active --quiet app-dev.lizardbyte.app.Sunshine.service
inspect "/dev/uinput writable"        test -w /dev/uinput
inspect "udev rule present"           test -f /etc/udev/rules.d/60-sunshine.rules
# The proof that counts is not a live process but a port that answers: a
# service that started and then hung would pass the previous check.
if timeout 5 bash -c 'echo > /dev/tcp/127.0.0.1/47990' 2>/dev/null; then
    pass "Sunshine's interface is listening on port 47990"
else
    fail "Sunshine's interface does not answer on port 47990"
fi

log_step "Cloud gaming"
inspect "Xbox Cloud Gaming menu entry" test -f "$HOME/.local/share/applications/xbox-cloud-gaming.desktop"
if grep -qa 'Xbox Cloud Gaming' "$STEAM_ROOT"/userdata/*/config/shortcuts.vdf 2>/dev/null; then
    pass "Xbox Cloud Gaming in the Steam library"
else
    fail "Xbox Cloud Gaming is not in the library"
fi
if grep -qa 'GeForce NOW' "$STEAM_ROOT"/userdata/*/config/shortcuts.vdf 2>/dev/null; then
    pass "GeForce NOW in the Steam library"
else
    fail "GeForce NOW is not in the library"
fi

# ---------------------------------------------------------------------------
printf '\n'
if [ "$ko" -eq 0 ]; then
    log_ok "verification passed: $ok checks, nothing missing"
    record "Final verification" VERIFIED "$ok checks passed"
    exit 0
fi
log_warn "verification: $ok checks passed, $ko entries missing"
record "Final verification" FAILED "$ko entries missing out of $((ok + ko))"
exit 1
