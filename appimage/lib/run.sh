#!/usr/bin/env bash
# The worker the launcher starts: it obtains privileges, runs the requested
# action and records the outcome where AppRun can read it.
#
# This runs inside the terminal window when there is one, and that placement is
# the point. sudo binds its timestamp to the terminal that created it, so a
# password collected by AppRun and used here would be invisible: every
# privileged step would ask again, or fail. Asking from inside the process tree
# that will do the work keeps one prompt for the whole run.

set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/gui.sh"

: "${LAUNCHER_ACTION:?LAUNCHER_ACTION is not set}"
: "${LAUNCHER_RUNDIR:?LAUNCHER_RUNDIR is not set}"
PAYLOAD="$HERE/../steamos-handheld-kit"

# The payload's shared library answers one question this layer needs - whether
# the account has a password at all - and one implementation of that answer is
# better than two that can drift apart.
HANDHELD_KIT_ROOT="$PAYLOAD"
export HANDHELD_KIT_ROOT
# shellcheck source=../../src/lib/common.sh
. "$PAYLOAD/lib/common.sh"

# Exactly one worker per run. The launcher starts a terminal window and falls
# back to a progress dialog when that window does not appear in time; a
# terminal that was merely slow would then produce a second worker. Creating
# the marker under noclobber makes that a race only one of them can win.
if ! (set -o noclobber; : > "$LAUNCHER_RUNDIR/started") 2>/dev/null; then
    printf 'Another window is already running this action.\n' >&2
    exit 1
fi

# The outcome is recorded whatever happens, a crash or a closed window
# included: the launcher waits for this file, and its absence would leave it
# waiting forever. A run that never reaches the command counts as failed.
status=1
record_status() {
    printf '%s\n' "$status" > "$LAUNCHER_RUNDIR/status.part"
    mv -f "$LAUNCHER_RUNDIR/status.part" "$LAUNCHER_RUNDIR/status"
}
trap 'record_status' EXIT

case "$LAUNCHER_ACTION" in
    install) command=("$PAYLOAD/setup.sh");                    needs_privileges=1 ;;
    dryrun)  command=("$PAYLOAD/setup.sh" --dry-run);          needs_privileges=0 ;;
    verify)  command=("$PAYLOAD/setup.sh" --verify);           needs_privileges=0 ;;
    remove)  command=("$PAYLOAD/teardown.sh" --confirm);       needs_privileges=1 ;;
    *)       printf 'Unknown action: %s\n' "$LAUNCHER_ACTION" >&2; status=2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# Privileges
#
# The password is held in a shell variable of this process alone: it is never
# written to disk, never passed as a command-line argument where the process
# list would show it, and never reaches the log. sudo reads it from standard
# input and stores only its own timestamp.
# ---------------------------------------------------------------------------
acquire_privileges() {
    if sudo -n true 2>/dev/null; then
        printf 'Administrator rights are already available.\n'
        return 0
    fi

    # With no password on the account there is nothing to ask for: sudo would
    # reject whatever were typed, three times over.
    if [ "$(password_status)" = "unset" ]; then
        printf 'This account has no password, so administrator rights cannot be granted.\n'
        return 1
    fi

    local attempt password
    for attempt in 1 2 3; do
        password="$(gui_password "Password for $SETUP_USER" || true)"
        if [ -z "$password" ]; then
            return 1
        fi
        if printf '%s\n' "$password" | sudo -S -p '' -v 2>/dev/null; then
            password=""
            printf 'Administrator rights obtained.\n'
            return 0
        fi
        password=""
        [ "$attempt" -lt 3 ] && gui_error "That password was not accepted. Please try again."
    done
    gui_error "The password was not accepted three times. No further attempts will be made."
    return 1
}

# ---------------------------------------------------------------------------
# A first boot has no password at all
#
# SteamOS ships the user account without one, and sudo accepts nothing until
# one exists - so on the machine this tool is most useful on, the very first
# run would otherwise fail at its first privileged step with a password box
# that can never be satisfied.
#
# `passwd` is what sets it. It needs no privileges, it changes nothing else,
# and it reads from a terminal - so this is offered exactly where this worker
# has one, which is the window the launcher opens for the run.
# ---------------------------------------------------------------------------
offer_to_set_password() {
    [ "$(password_status)" = "unset" ] || return 0

    if [ "${LAUNCHER_IN_TERMINAL:-0}" != "1" ]; then
        gui_error "This handheld has no administrator password yet, and the steps that install the plugin system cannot run without one.

Open a terminal, run:

    passwd

then start this again."
        return 1
    fi

    gui_question "This handheld has no administrator password yet.

SteamOS ships without one, and installing the plugin system needs it. You can set it now: the window behind this one will ask you to type a new password twice.

Nothing else on the handheld changes, and you can skip this and install everything else instead.

Set a password now?" || return 1

    printf '\n'
    printf 'Setting the password for %s.\n' "$SETUP_USER"
    printf 'Nothing appears as you type. You will be asked for it twice.\n\n'

    local attempt
    for attempt in 1 2 3; do
        if passwd; then
            printf '\nPassword set.\n\n'
            # The window that just took the new password can take it once more
            # for sudo, which beats a dialog appearing over the terminal the
            # user is already typing in. A refusal here is not fatal:
            # acquire_privileges asks in its own way immediately afterwards.
            printf 'Type it once more to grant the administrator rights this run needs.\n'
            sudo -v || true
            return 0
        fi
        printf '\nThat did not work.\n'
    done
    return 1
}

if [ "$needs_privileges" = "1" ]; then
    # Should the ticket ever lapse mid-run with no terminal to type into, sudo
    # reaches for this helper instead of waiting for input that cannot come.
    export SUDO_ASKPASS="$HERE/askpass.sh"

    offer_to_set_password || true

    if ! acquire_privileges; then
        if gui_question "Continue without administrator rights?

The steps that need them - installing the plugin system, and removing it - will be reported as not done. Everything else works normally."; then
            printf 'Continuing without administrator rights.\n'
            # Read by sudo_begin and the privileged steps, which then skip
            # instead of asking for the password a second time.
            export HANDHELD_KIT_NO_PRIVILEGES=1
        else
            printf 'Cancelled: nothing was changed.\n'
            status=1
            exit 1
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
status=0
"${command[@]}" || status=$?

if [ "${LAUNCHER_IN_TERMINAL:-0}" = "1" ]; then
    printf '\n'
    printf 'Press Enter to close this window.\n'
    read -r _ || true
fi

exit "$status"
