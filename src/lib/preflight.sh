#!/usr/bin/env bash
# Preliminary checks: establish that this machine can be worked on and that the
# minimum conditions exist. Nothing is modified here.
#
# A check that fails outright stops the run. A check that merely reports an
# unfamiliar situation warns and lets the run continue: the tool is written for
# SteamOS on an AMD handheld, and everything outside that description is
# reported honestly rather than blocked on a guess.

preflight() {
    log_step "Preliminary checks"
    local errors=0

    # --- Operating system ---------------------------------------------------
    if [ -r /etc/os-release ]; then
        local os_name build
        os_name="$(. /etc/os-release && echo "${NAME:-unknown}")"
        build="$(. /etc/os-release && echo "${BUILD_ID:-unknown}")"
        if [ "$os_name" = "SteamOS" ]; then
            log_ok "SteamOS detected (build $build)"
        else
            log_warn "system '$os_name': this tool is written for SteamOS, continuing with care"
        fi
    else
        log_warn "/etc/os-release is unreadable: the system cannot be identified"
    fi

    # --- Architecture -------------------------------------------------------
    # Proton-GE, the Decky loader binary and the EmuDeck AppImage are all
    # published for x86_64 only. On any other architecture this tool would
    # install a set of components that cannot run.
    local arch
    arch="$(uname -m)"
    if [ "$arch" = "x86_64" ]; then
        log_ok "architecture: $arch"
    else
        log_err "architecture '$arch' is not supported: the components installed here are x86_64 only"
        errors=$((errors + 1))
    fi

    # --- Machine ------------------------------------------------------------
    log_ok "machine: $DEVICE_VENDOR $DEVICE_PRODUCT"
    if device_is_asus || device_is_steam_deck; then
        :
    else
        log_warn "this vendor has not been exercised: the hardware checks report what they find,"
        log_warn "and the components installed do not depend on the model"
    fi

    # --- User ---------------------------------------------------------------
    if [ "$(id -u)" -eq 0 ]; then
        log_err "do not run this as root: run it as your normal user"
        errors=$((errors + 1))
    fi
    if ! id -nG | tr ' ' '\n' | grep -qx wheel; then
        log_warn "this user is not in the wheel group: the privileged steps will fail"
    fi

    # --- Required commands --------------------------------------------------
    local missing=()
    for c in curl flatpak python3 systemctl tar unzip; do
        have "$c" || missing+=("$c")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        log_err "missing commands: ${missing[*]}"
        errors=$((errors + 1))
    else
        log_ok "every required command is present"
    fi

    # --- Network ------------------------------------------------------------
    if net_available; then
        log_ok "Flathub is reachable"
    else
        log_err "Flathub is unreachable: nothing can be installed without a network"
        errors=$((errors + 1))
    fi

    # --- Disk space ---------------------------------------------------------
    local free_home
    free_home="$(df -BG --output=avail "$HOME" 2>/dev/null | tail -1 | tr -dc '0-9')"
    if [ -n "$free_home" ] && [ "$free_home" -lt 10 ]; then
        log_err "only ${free_home}GB free in $HOME: not enough space"
        errors=$((errors + 1))
    else
        log_ok "space in $HOME: ${free_home:-?}GB free"
    fi

    # --- Removable storage --------------------------------------------------
    if sd_mounted; then
        local free_sd
        free_sd="$(df -BG --output=avail "$SD_MOUNT" 2>/dev/null | tail -1 | tr -dc '0-9')"
        log_ok "memory card mounted at $SD_MOUNT (${free_sd:-?}GB free)"
    else
        log_warn "no memory card mounted: ROM folders will go to the internal drive"
    fi

    # --- Graphical session --------------------------------------------------
    # EmuDeck and some third-party installers open windows: without a display
    # they degrade to a manual step.
    if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        log_ok "graphical session available"
    else
        log_warn "no graphical session: the steps that open windows will be adapted"
    fi

    [ "$errors" -eq 0 ]
}
