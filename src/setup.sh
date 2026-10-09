#!/usr/bin/env bash
# Post-installation setup for an AMD gaming handheld running SteamOS.
# Re-runnable: every step checks the current state before acting.
#
#   ./setup.sh --dry-run          show what it would do, installing nothing
#   ./setup.sh                    full run
#   ./setup.sh --only 30-decky    run a single module
#   ./setup.sh --verify           run the final verification only

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Suspend inhibition.
# The setup downloads around a gigabyte: while transfers run nobody touches the
# device, which suspends itself after a few minutes and leaves truncated
# archives behind. The script therefore re-executes itself under
# systemd-inhibit.
#
# The permission is not always granted: polkit gives it to the session attached
# to the screen and denies it to a remote shell, which occupies no seat. The
# inhibition stays optional - it is attempted, and when unavailable the run
# continues with a warning. An accessory safeguard must not block the start.
# ---------------------------------------------------------------------------
if [ -z "${HANDHELD_KIT_INHIBITED:-}" ] && command -v systemd-inhibit >/dev/null 2>&1; then
    export HANDHELD_KIT_INHIBITED=1
    for what in idle:sleep idle; do
        if systemd-inhibit --what="$what" --who="steamos-handheld-kit" --why="probe" true 2>/dev/null; then
            exec systemd-inhibit --what="$what" --who="steamos-handheld-kit" \
                 --why="post-installation setup in progress" \
                 "$0" "$@"
        fi
    done
    printf '\033[33mWarning: automatic suspend could not be inhibited.\033[0m\n'
    printf '\033[33mIf the device suspends during a download, start the script again:\033[0m\n'
    printf '\033[33mit resumes from where it stopped.\033[0m\n\n'
fi

HANDHELD_KIT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export HANDHELD_KIT_ROOT

DRY_RUN=0
ONLY=""
SKIP=""
LOG_FILE="$HOME/steamos-handheld-kit.log"

usage() {
    cat <<'END'
Post-installation setup - AMD gaming handhelds running SteamOS

  --dry-run           print every action without carrying it out
  --only <module>     run only the named module (a fragment works: "decky")
  --skip <module>     exclude the named module from a full run
  --verify            run the final verification only
  --log <file>        log file path (default: ~/steamos-handheld-kit.log)
  --version           print the version and exit
  -h, --help          this message

Available modules:
  10-hardware-check   verify hardware enablement (installs nothing)
  20-flatpak-base     Flathub, Flatseal, Bazaar
  30-decky            Decky Loader and plugins
  40-proton           ProtonPlus and Proton-GE
  50-launchers        Heroic Games Launcher and Lutris
  60-emulation        ROM folders on the memory card, and EmuDeck
  70-remote-access    Sunshine streaming server
  80-utilities        SyncThingy
  85-cloud-gaming     GeForce NOW, Chrome, Edge, Xbox Cloud Gaming
  88-steam-config     writes to Steam's own configuration
  90-verify           checks the running system
END
}

# An option that takes a value, given none.
needs_value() { printf '%s needs a value\n\n' "$1" >&2; usage >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --only)    [ -n "${2:-}" ] || needs_value "$1"; ONLY="$2"; shift 2 ;;
        --skip)    [ -n "${2:-}" ] || needs_value "$1"; SKIP="$2"; shift 2 ;;
        --verify)  ONLY="90-verify"; shift ;;
        --log)     [ -n "${2:-}" ] || needs_value "$1"; LOG_FILE="$2"; shift 2 ;;
        --version) cat "$HANDHELD_KIT_ROOT/VERSION"; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

# On exit the privileges are released and the temporary outcome file removed:
# the durable copy stays in ~/steamos-handheld-kit-results.tsv, and without
# this removal every run would leave one behind in the temporary directory.
# sudo_end comes from common.sh, which an early exit may not have loaded yet.
RESULTS_FILE="$(mktemp -t steamos-handheld-kit-results.XXXXXX)"
cleanup_on_exit() {
    sudo_end 2>/dev/null || true
    rm -f "$RESULTS_FILE"
}
trap 'cleanup_on_exit' EXIT

export DRY_RUN LOG_FILE RESULTS_FILE
mkdir -p "$(dirname "$LOG_FILE")"
: > "$RESULTS_FILE"

# shellcheck source=lib/common.sh
. "$HANDHELD_KIT_ROOT/lib/common.sh"

printf '%s%s\n' "$C_BOLD" "================================================================"
printf '  SteamOS Handheld Kit %s\n' "$SETUP_VERSION"
[ "$DRY_RUN" = "1" ] && printf '  %sDRY RUN: no change will be applied%s\n' "$C_YELLOW" "$C_RESET"
printf '  log: %s\n' "$LOG_FILE"
printf '%s%s\n' "================================================================" "$C_RESET"

_write_log "########## start: $(_stamp) version=$SETUP_VERSION dry_run=$DRY_RUN only='$ONLY' skip='$SKIP' ##########"

# ---------------------------------------------------------------------------
# Preliminary checks
# ---------------------------------------------------------------------------
# shellcheck source=lib/preflight.sh
. "$HANDHELD_KIT_ROOT/lib/preflight.sh"
preflight || { log_err "preliminary checks not passed: stopping"; exit 1; }

# ---------------------------------------------------------------------------
# Module selection, shared by the privilege decision and the runner so the two
# cannot disagree. Returns 0 to run the module, 1 when --only leaves it out and
# 2 when --skip excludes it.
# ---------------------------------------------------------------------------
module_choice() {
    if [ -n "$ONLY" ] && [[ "$1" != *"$ONLY"* ]]; then
        return 1
    fi
    if [ -n "$SKIP" ] && [[ "$1" == *"$SKIP"* ]]; then
        return 2
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Privileges: asked for once, and only when they are actually needed.
# Of all the modules only the Decky installation writes outside the home
# directory; running any of the others must not ask for a password that would
# then go unused.
# ---------------------------------------------------------------------------
MODULES_WITHOUT_PRIVILEGES="88-steam-config 90-verify"
needs_sudo=0
for module in "$HANDHELD_KIT_ROOT"/modules/*.sh; do
    name="$(basename "$module" .sh)"
    module_choice "$name" || continue
    case " $MODULES_WITHOUT_PRIVILEGES " in
        *" $name "*) ;;
        *) needs_sudo=1 ;;
    esac
done
if [ "$needs_sudo" = "1" ]; then
    sudo_begin
else
    log_info "the selected modules need no privileges"
fi

# ---------------------------------------------------------------------------
# Module execution. Each runs in its own process: a module that fails is
# recorded and does not stop the ones after it.
# ---------------------------------------------------------------------------
modules_run=0
modules_failed=0

for module in "$HANDHELD_KIT_ROOT"/modules/*.sh; do
    name="$(basename "$module" .sh)"

    choice=0
    module_choice "$name" || choice=$?
    if [ "$choice" = "1" ]; then
        continue
    fi
    if [ "$choice" = "2" ]; then
        log_warn "module skipped on request: $name"
        record "$name" SKIPPED "excluded with --skip"
        continue
    fi

    log_module "$name"
    rc=0
    bash "$module" || rc=$?
    modules_run=$((modules_run + 1))
    if [ "$rc" -ne 0 ]; then
        modules_failed=$((modules_failed + 1))
        log_err "module $name ended with status $rc"
        # An exit status is observed, not predicted, in a dry run too.
        OBSERVATION_ONLY=1 record "$name" FAILED "exit status $rc"
    fi
done

if [ "$modules_run" -eq 0 ]; then
    log_err "no module matches '$ONLY'"
    exit 2
fi

# ---------------------------------------------------------------------------
# Summary: one line per component, each with its own outcome
# ---------------------------------------------------------------------------
printf '\n%s%s\n' "$C_BOLD" "================================================================"
printf '  SUMMARY\n'
printf '%s%s\n\n' "================================================================" "$C_RESET"

print_results

failed="$(grep -c $'\tFAILED\t' "$RESULTS_FILE" 2>/dev/null || true)"
failed="${failed:-0}"
manual="$(grep -c $'\tMANUAL\t' "$RESULTS_FILE" 2>/dev/null || true)"
manual="${manual:-0}"

printf '\n'
if [ "$manual" -gt 0 ]; then
    printf '  %s%s steps need you: look for MANUAL in the list above%s\n' \
        "$C_YELLOW" "$manual" "$C_RESET"
fi

cp "$RESULTS_FILE" "$HOME/steamos-handheld-kit-results.tsv" 2>/dev/null || true
printf '  full log:          %s\n' "$LOG_FILE"
printf '  outcomes as a table: %s\n\n' "$HOME/steamos-handheld-kit-results.tsv"

if [ "$DRY_RUN" = "1" ]; then
    printf '  %sDry run finished: nothing was changed.%s\n' "$C_BLUE" "$C_RESET"
    printf '  The PLANNED entries are what a real run would install.\n'
    printf '  To carry it out, run it again without %s--dry-run%s.\n\n' "$C_BOLD" "$C_RESET"
    exit 0
fi

if [ "$failed" -gt 0 ] || [ "$modules_failed" -gt 0 ]; then
    printf '  %sOutcome: %s entries failed. Re-run the single module with --only once fixed.%s\n\n' \
        "$C_RED" "$failed" "$C_RESET"
    exit 1
fi

printf '  %sOutcome: completed with no errors.%s\n\n' "$C_GREEN" "$C_RESET"
