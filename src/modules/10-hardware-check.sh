#!/usr/bin/env bash
# Verify that the hardware enablement SteamOS already provides is working.
#
# Nothing is installed here, deliberately. SteamOS ships inputplumber.service
# with per-model profiles, and it claims the physical gamepad exclusively while
# publishing a virtual one that Steam talks to. Adding a second handheld daemon
# on top - Handheld Daemon and its kin - puts two processes in contention for
# the same HID device, and the handheld ends up with no working controller.
# This layer is checked, never replaced.

set -Eeuo pipefail
HANDHELD_KIT_ROOT="${HANDHELD_KIT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$HANDHELD_KIT_ROOT/lib/common.sh"

# Every outcome here is observed, in a dry run as much as in a real one.
export OBSERVATION_ONLY=1
status=0

# --- InputPlumber: the controller manager -----------------------------------
log_step "InputPlumber"
if systemctl is-active --quiet inputplumber 2>/dev/null; then
    version="$(inputplumber --version 2>/dev/null | head -1 || echo 'version unreadable')"
    log_ok "active - $version"

    # A device profile declares which machines it covers by naming their DMI
    # fields, so the profile covering this one is the file naming this
    # machine's. The board name is tried first because that is the field the
    # profiles key on; the product name is the fallback for profiles written
    # against it instead.
    #
    # -F: these values carry characters a regular expression would read as
    # operators, and the match wanted here is the literal string.
    profile=""
    for dmi_value in "$DEVICE_BOARD" "$DEVICE_PRODUCT"; do
        # Too short a value matches half the directory by accident.
        [ "${#dmi_value}" -ge 4 ] || continue
        profile="$(grep -rlsF --include='*.yaml' -e "$dmi_value" /usr/share/inputplumber/devices/ 2>/dev/null | head -1 || true)"
        [ -n "$profile" ] && break
    done

    if [ -n "$profile" ]; then
        log_ok "device profile present: $(basename "$profile")"
        record "InputPlumber" VERIFIED "$(basename "$profile")"
    else
        log_warn "no installed profile names this product: the generic profile applies"
        record "InputPlumber" VERIFIED "active, no model-specific profile"
    fi
else
    log_err "inputplumber is not active: the built-in controls may not respond"
    record "InputPlumber" FAILED "service not active"
    status=1
fi

# --- Virtual gamepad ---------------------------------------------------------
log_step "Controller"
if grep -q 'X-Box 360 pad' /proc/bus/input/devices 2>/dev/null; then
    log_ok "virtual gamepad present: Steam sees a standard controller"
    record "Virtual gamepad" VERIFIED "emulated by InputPlumber"
else
    log_warn "no virtual gamepad detected"
    record "Virtual gamepad" FAILED "absent from /proc/bus/input/devices"
    status=1
fi

# --- Vendor kernel modules ---------------------------------------------------
# Which modules carry the extra controls depends on the vendor, so only the
# ones this machine should have are looked for.
log_step "Kernel modules"
expected=()
if device_is_asus; then
    expected=(hid_asus_ally asus_armoury asus_wmi)
elif device_is_steam_deck; then
    expected=(hid_steam)
fi

if [ "${#expected[@]}" -eq 0 ]; then
    log_info "no vendor module set is known for $DEVICE_VENDOR: skipping this check"
    record "Vendor kernel modules" SKIPPED "$DEVICE_VENDOR not covered"
else
    missing=()
    for m in "${expected[@]}"; do
        if lsmod 2>/dev/null | awk '{print $1}' | grep -qx "$m"; then
            log_ok "$m loaded"
        else
            log_warn "$m not loaded"
            missing+=("$m")
        fi
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        record "Vendor kernel modules" VERIFIED "${expected[*]}"
    else
        record "Vendor kernel modules" FAILED "missing: ${missing[*]}"
    fi
fi

# --- Power profiles, TDP and cooling ----------------------------------------
log_step "Power and cooling"
if [ -r /sys/firmware/acpi/platform_profile ]; then
    current="$(cat /sys/firmware/acpi/platform_profile 2>/dev/null)"
    choices="$(cat /sys/firmware/acpi/platform_profile_choices 2>/dev/null)"
    log_ok "active profile: $current (available: $choices)"
    record "Power profiles" VERIFIED "$current"
else
    log_warn "platform_profile is not exposed by the kernel"
    record "Power profiles" FAILED "interface absent"
fi

# Two routes reach the power limits: the ASUS firmware-attributes interface,
# and the generic amdgpu power cap every AMD part exposes through hwmon.
tdp_source=""
if [ -d /sys/class/firmware-attributes/asus-armoury/attributes/ppt_pl1_spl ]; then
    tdp_source="asus-armoury (ppt_pl1_spl, ppt_pl2_sppt, ppt_pl3_fppt)"
elif compgen -G "/sys/class/hwmon/*/power1_cap" >/dev/null 2>&1; then
    tdp_source="hwmon power1_cap"
fi
if [ -n "$tdp_source" ]; then
    log_ok "TDP controls exposed: $tdp_source"
    record "TDP controls" VERIFIED "$tdp_source"
else
    log_warn "no TDP control interface found"
    record "TDP controls" FAILED "no interface exposed"
fi

fan_source=""
for hwmon_name in /sys/class/hwmon/*/name; do
    [ -r "$hwmon_name" ] || continue
    case "$(cat "$hwmon_name")" in
        asus_custom_fan_curve|steamdeck_hwmon|jupiter)
            fan_source="$(cat "$hwmon_name")"
            break
            ;;
    esac
done
if [ -n "$fan_source" ]; then
    log_ok "fan control present: $fan_source"
    record "Fan control" VERIFIED "$fan_source"
elif device_is_asus || device_is_steam_deck; then
    log_warn "no adjustable fan curve interface found"
    record "Fan control" FAILED "no interface exposed"
else
    # The interfaces looked for belong to these two vendors: on any other an
    # absence says nothing about whether the fan is working.
    log_info "no fan interface is known for $DEVICE_VENDOR: skipping this check"
    record "Fan control" SKIPPED "no known fan interface for $DEVICE_VENDOR"
fi

# --- Decky plugins that fight this hardware ---------------------------------
# PowerTools and Fantastic drive the Steam Deck's own registers. On a Steam
# Deck they are the right tool; on other handhelds they contend with the
# vendor driver over the same registers, and the result is neither one nor the
# other in control.
if ! device_is_steam_deck; then
    if [ -d "$DECKY_DIR/plugins/PowerTools" ] || [ -d "$DECKY_DIR/plugins/Fantastic" ]; then
        log_warn "PowerTools or Fantastic detected: written for Steam Deck hardware, on this"
        log_warn "machine they compete with the vendor driver for the same registers."
        record "Conflicting plugins" MANUAL "PowerTools/Fantastic present: removal advised"
    fi
fi

exit "$status"
