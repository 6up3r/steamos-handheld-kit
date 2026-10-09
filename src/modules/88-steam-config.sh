#!/usr/bin/env bash
# Writes to Steam's configuration, with Steam closed.
#
# Steam loads shortcuts.vdf and config.vdf at start and rewrites them from the
# copy it holds in memory when it exits: editing them while it runs means
# watching them revert, with no message of any kind. Every write is therefore
# gathered here, inside a single window where Steam is stopped and then
# started again.

set -Eeuo pipefail
HANDHELD_KIT_ROOT="${HANDHELD_KIT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$HANDHELD_KIT_ROOT/lib/common.sh"

status=0
XBOX_URL="https://www.xbox.com/play"
TOOL="$HANDHELD_KIT_ROOT/lib/steam_config.py"

# ---------------------------------------------------------------------------
# What to write: decided before Steam is touched, so it is never stopped for
# nothing.
# ---------------------------------------------------------------------------
log_step "Preparation"

profile="$(ls -d "$STEAM_ROOT"/userdata/*/ 2>/dev/null | head -1)"
if [ -z "$profile" ]; then
    log_err "no Steam profile: sign in to Steam at least once"
    record "Steam configuration" FAILED "user profile absent"
    exit 1
fi
profile="${profile%/}"
log_ok "profile: $(basename "$profile")"

config_vdf="$STEAM_ROOT/config/config.vdf"

# Which Proton-GE version to make the default: read from the filesystem rather
# than from what the previous module believes it did, so this module still runs
# on its own and still works when Proton-GE was already there.
proton_ge="$(latest_proton_ge)"
if [ -n "$proton_ge" ]; then
    log_ok "newest installed Proton-GE: $proton_ge"
else
    log_warn "no Proton-GE version in $COMPAT_DIR: the default will not be set"
fi

if [ "$DRY_RUN" = "1" ]; then
    printf '  %s[dry run]%s would stop Steam and add the Xbox Cloud Gaming entry\n' "$C_YELLOW" "$C_RESET"
    [ -n "$proton_ge" ] && printf '  %s[dry run]%s would set %s as the global default\n' \
        "$C_YELLOW" "$C_RESET" "$proton_ge"
    printf '  %s[dry run]%s would start Steam again\n' "$C_YELLOW" "$C_RESET"
    record "Xbox Cloud Gaming in library" PLANNED "non-Steam entry"
    record "Proton-GE default" PLANNED "${proton_ge:-the newest Proton-GE installed}"
    exit 0
fi

ensure_python_vdf || {
    log_err "the Python vdf module is unavailable: the configuration cannot be written"
    record "Steam configuration" FAILED "vdf module absent"
    exit 1
}

# ---------------------------------------------------------------------------
# Stopping Steam
# ---------------------------------------------------------------------------
steam_was_running=0
if steam_running; then
    steam_was_running=1
    log_step "Stopping Steam"
    log_info "asking Steam to shut down cleanly"
    steam -shutdown >/dev/null 2>&1 || true

    for _ in $(seq 1 30); do
        steam_running || break
        sleep 1
    done

    if steam_running; then
        log_err "Steam did not close within 30 seconds: no change applied"
        log_err "close it by hand and run again with --only 88-steam-config"
        record "Steam configuration" FAILED "Steam still running"
        exit 1
    fi
    log_ok "Steam closed"
    # Steam writes its files while shutting down: let it finish.
    sleep 2
else
    log_info "Steam was not running"
fi

# ---------------------------------------------------------------------------
# The writes
# ---------------------------------------------------------------------------
log_step "Xbox Cloud Gaming entry in the library"

edge_arguments="run --branch=stable --arch=x86_64 com.microsoft.Edge"
edge_arguments+=" --window-size=1280,800 --force-device-scale-factor=1.25"
edge_arguments+=" --device-scale-factor=1.25 --kiosk \"$XBOX_URL\""

python_command=("$PYTHON_VDF" "$TOOL"
    --userdata "$profile"
    --config "$config_vdf"
    --shortcut-name "Xbox Cloud Gaming"
    --shortcut-exe "/usr/bin/flatpak"
    --shortcut-args "$edge_arguments"
    --shortcut-dir "/usr/bin/")

[ -n "$proton_ge" ] && python_command+=(--proton "$proton_ge")

if run_visible "writing Steam's configuration" "${python_command[@]}"; then
    record "Xbox Cloud Gaming in library" INSTALLED "non-Steam entry"
    [ -n "$proton_ge" ] && record "Proton-GE default" INSTALLED "$proton_ge"
    log_ok "configuration written (backups sit next to the originals)"
else
    log_err "writing the configuration failed"
    record "Steam configuration" FAILED "the tool errored"
    status=1
fi

# ---------------------------------------------------------------------------
# Starting Steam again
# ---------------------------------------------------------------------------
# The variables that tie a process to the graphical session do not exist in a
# remote shell, and without them Steam starts and dies for want of a
# compositor. They do exist in the environment of the desktop's own processes,
# which the kernel exposes through /proc/<pid>/environ: they are read from
# there.
recover_graphical_environment() {
    local pid
    pid="$(pgrep -x plasmashell 2>/dev/null | head -1)"
    [ -z "$pid" ] && pid="$(pgrep -x kwin_wayland 2>/dev/null | head -1)"
    [ -z "$pid" ] && pid="$(pgrep -x gnome-shell 2>/dev/null | head -1)"
    [ -z "$pid" ] && return 1
    [ -r "/proc/$pid/environ" ] || return 1

    local name value
    while IFS='=' read -r -d '' name value; do
        case "$name" in
            DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|XAUTHORITY)
                export "$name=$value"
                ;;
        esac
    done < "/proc/$pid/environ"
    return 0
}

if [ "$steam_was_running" = "1" ]; then
    log_step "Starting Steam again"
    if have steam; then
        # Steam has to be handed to the user's session manager, which already
        # holds the complete graphical environment. Starting it as a child of
        # the terminal instead (nohup, &) ties it to this session: it starts,
        # does not find the context it expects and exits shortly after,
        # leaving the physical gamepad claimed by InputPlumber and no virtual
        # one in its place - that is, a handheld with no controller.
        if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
            recover_graphical_environment \
                && log_ok "session context recovered" \
                || log_warn "no desktop session found"
        fi

        started=0
        if have systemd-run; then
            if systemd-run --user --collect --unit="steam-handheld-kit" steam >/dev/null 2>&1; then
                started=1
            fi
        fi
        if [ "$started" = "0" ]; then
            log_warn "starting it as a service failed: trying a direct start"
            setsid steam >/dev/null 2>&1 &
            disown 2>/dev/null || true
        fi

        # Starting takes several seconds: wait until the process appears
        # instead of trusting an arbitrary moment.
        for _ in $(seq 1 20); do
            steam_running && break
            sleep 1
        done

        if steam_running; then
            log_ok "Steam started again"
            # Steam is what creates the virtual gamepad: its reappearance is
            # the proof that the restart really worked.
            for _ in $(seq 1 15); do
                grep -q 'X-Box 360 pad' /proc/bus/input/devices 2>/dev/null && break
                sleep 1
            done
            if grep -q 'X-Box 360 pad' /proc/bus/input/devices 2>/dev/null; then
                log_ok "virtual gamepad restored"
            else
                log_warn "the virtual gamepad has not reappeared yet: wait for Steam to finish loading"
            fi
        else
            log_err "Steam did not start again: start it from the menu before using the handheld"
            record "Steam restart" MANUAL "start Steam from the application menu"
        fi
    fi
else
    log_info "Steam was not running: the changes will be read at its next start"
fi

exit "$status"
