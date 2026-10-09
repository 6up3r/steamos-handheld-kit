#!/usr/bin/env bash
# Helpers shared by setup.sh, teardown.sh, every module and the graphical
# launcher. Sourced, never executed directly.
#
# shellcheck disable=SC2034
# The variables defined here are this library's public surface: every one of
# them is read by the modules that source it, which a check of this file on its
# own cannot see.

[ -n "${HANDHELD_KIT_COMMON_LOADED:-}" ] && return 0
HANDHELD_KIT_COMMON_LOADED=1

# --------------------------------------------------------------------------
# Defaults, overridable through the environment inherited from setup.sh
# --------------------------------------------------------------------------
: "${HANDHELD_KIT_ROOT:?HANDHELD_KIT_ROOT is not set}"
: "${DRY_RUN:=0}"
: "${LOG_FILE:=$HOME/steamos-handheld-kit.log}"
: "${RESULTS_FILE:=${TMPDIR:-/tmp}/steamos-handheld-kit-results.tsv}"

SETUP_VERSION="$(cat "$HANDHELD_KIT_ROOT/VERSION" 2>/dev/null || echo "unknown")"

# The login name is read once. A session started by a service manager can have
# USER unset, and every path below would then be built from an empty string.
SETUP_USER="${USER:-$(id -un)}"

COMPAT_DIR="$HOME/.steam/root/compatibilitytools.d"
STEAM_ROOT="$HOME/.local/share/Steam"
DECKY_DIR="$HOME/homebrew"
VENV_DIR="$HOME/.local/share/steamos-handheld-kit/venv"

# --------------------------------------------------------------------------
# Colours: terminal only, so the log file stays plain text
# --------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[31m';  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
    C_RESET=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_CYAN=
fi

# --------------------------------------------------------------------------
# Logging
# --------------------------------------------------------------------------
_stamp() { date '+%Y-%m-%d %H:%M:%S'; }

_write_log() { printf '%s  %s\n' "$(_stamp)" "$*" >> "$LOG_FILE"; }

log_info()  { printf '%s  %s\n' "${C_DIM}$(_stamp)${C_RESET}" "$*";                 _write_log "INFO  $*"; }
log_ok()    { printf '%s  %s%s%s\n' "${C_DIM}$(_stamp)${C_RESET}" "$C_GREEN"  "$*" "$C_RESET"; _write_log "OK    $*"; }
log_warn()  { printf '%s  %s%s%s\n' "${C_DIM}$(_stamp)${C_RESET}" "$C_YELLOW" "$*" "$C_RESET"; _write_log "WARN  $*"; }
log_err()   { printf '%s  %s%s%s\n' "${C_DIM}$(_stamp)${C_RESET}" "$C_RED"    "$*" "$C_RESET" >&2; _write_log "ERR   $*"; }

# Confirmation of an action just performed: silent in dry-run mode, where the
# action was not carried out and announcing its success would be a lie.
log_ok_done() { [ "$DRY_RUN" = "1" ] && return 0; log_ok "$@"; }

log_step() {
    printf '\n%s%s>> %s%s\n' "$C_BOLD" "$C_CYAN" "$*" "$C_RESET"
    _write_log "STEP  $*"
}

log_module() {
    printf '\n%s%s%s%s\n' "$C_BOLD" "$C_BLUE" "=== $* ===" "$C_RESET"
    _write_log "===== $* ====="
}

# --------------------------------------------------------------------------
# Outcomes for the final summary: component <TAB> outcome <TAB> detail
# States: INSTALLED PRESENT UPDATED SKIPPED FAILED MANUAL VERIFIED REMOVED PLANNED
# --------------------------------------------------------------------------
record() {
    local component="$1" outcome="$2" detail="${3:-}"
    # In dry-run mode nothing is carried out, so an outcome describing an
    # action (installed, updated, removed) would be a prediction dressed up as
    # a fact, and is declared as such. Outcomes that come from a real
    # observation - PRESENT, VERIFIED, MANUAL - hold either way and are left
    # untouched. A module that only observes sets OBSERVATION_ONLY=1, and its
    # FAILED is then a finding rather than a prediction.
    if [ "$DRY_RUN" = "1" ] && [ "${OBSERVATION_ONLY:-0}" != "1" ]; then
        case "$outcome" in
            INSTALLED|UPDATED|REMOVED|FAILED) outcome="PLANNED" ;;
        esac
    fi
    printf '%s\t%s\t%s\n' "$component" "$outcome" "$detail" >> "$RESULTS_FILE"
}

# One line per recorded outcome, coloured by state.
print_results() {
    local component outcome detail colour
    if [ ! -s "$RESULTS_FILE" ]; then
        printf '  (no outcome recorded)\n'
        return 0
    fi
    while IFS=$'\t' read -r component outcome detail; do
        case "$outcome" in
            INSTALLED|UPDATED|VERIFIED|REMOVED) colour="$C_GREEN" ;;
            PRESENT)                            colour="$C_CYAN"  ;;
            PLANNED)                            colour="$C_BLUE"  ;;
            SKIPPED|MANUAL)                     colour="$C_YELLOW";;
            FAILED)                             colour="$C_RED"   ;;
            *)                                  colour=""         ;;
        esac
        printf '  %s%-12s%s %-34s %s%s%s\n' \
            "$colour" "$outcome" "$C_RESET" "$component" "$C_DIM" "$detail" "$C_RESET"
    done < "$RESULTS_FILE"
}

# --------------------------------------------------------------------------
# Traced execution. In dry-run mode it prints and does not execute.
# Returns the command's real exit status: the caller checks it.
# --------------------------------------------------------------------------
run() {
    local description="$1"; shift
    if [ "$DRY_RUN" = "1" ]; then
        printf '  %s[dry run]%s %s\n' "$C_YELLOW" "$C_RESET" "$description"
        printf '            %s%s%s\n' "$C_DIM" "$*" "$C_RESET"
        _write_log "DRY   $description :: $*"
        return 0
    fi
    log_info "$description"
    _write_log "EXEC  $*"
    if "$@" >> "$LOG_FILE" 2>&1; then
        return 0
    else
        local rc=$?
        log_err "failed ($rc): $description - details in $LOG_FILE"
        return $rc
    fi
}

# Like run() but shows the output on screen: for long, talkative commands.
run_visible() {
    local description="$1"; shift
    if [ "$DRY_RUN" = "1" ]; then
        printf '  %s[dry run]%s %s\n' "$C_YELLOW" "$C_RESET" "$description"
        printf '            %s%s%s\n' "$C_DIM" "$*" "$C_RESET"
        _write_log "DRY   $description :: $*"
        return 0
    fi
    log_info "$description"
    _write_log "EXEC  $*"
    "$@" 2>&1 | tee -a "$LOG_FILE"
    return "${PIPESTATUS[0]}"
}

# --------------------------------------------------------------------------
# State queries
# --------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

flatpak_has() { flatpak info "$1" >/dev/null 2>&1; }

steam_running() { pgrep -x steam >/dev/null 2>&1; }

# --------------------------------------------------------------------------
# Whether this account has a password sudo could ever accept.
#
# A freshly installed SteamOS leaves the user account without one, and in that
# state sudo refuses everything typed at it: asking produces three rejections
# and no explanation of the real problem. `passwd -S` reports the account's own
# status to its owner without any privilege - P for a usable password, L for a
# locked one, NP for none at all.
#
# An answer that cannot be read comes back as "unknown" rather than as
# "unset": the caller then behaves exactly as it did before instead of
# refusing to work on the strength of a guess.
# --------------------------------------------------------------------------
password_status() {
    local state
    state="$(passwd -S "$SETUP_USER" 2>/dev/null | awk '{print $2}')"
    case "$state" in
        P)    printf 'set\n' ;;
        L|NP) printf 'unset\n' ;;
        *)    printf 'unknown\n' ;;
    esac
    return 0
}

# --------------------------------------------------------------------------
# Machine identity, read from the firmware tables the kernel exposes.
#
# Handheld hardware enablement differs per vendor - which kernel modules carry
# the TDP and fan controls, which Decky plugins are appropriate - so the checks
# branch on this rather than on a model name compiled into the script.
# --------------------------------------------------------------------------
DEVICE_VENDOR="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo unknown)"
DEVICE_PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"
# The board name is the field handheld device profiles actually key on, and it
# is the more discriminating of the two: a product name carries marketing text
# and sometimes repeats the board code inside itself.
DEVICE_BOARD="$(cat /sys/class/dmi/id/board_name 2>/dev/null || echo unknown)"

device_is_steam_deck() { case "$DEVICE_PRODUCT" in *Jupiter*|*Galileo*) return 0 ;; *) return 1 ;; esac; }
# ASUS spells its vendor string several ways - "ASUS", "ASUSTeK COMPUTER INC."
# - and every one of them contains the shorter form.
device_is_asus()       { case "$DEVICE_VENDOR"  in *ASUS*) return 0 ;; *) return 1 ;; esac; }

# --------------------------------------------------------------------------
# Removable storage, where ROM libraries are meant to live.
#
# SteamOS mounts removable media under /run/media/<user>/<label>, and older
# builds under /run/media/<label>: both the login name and the card's label
# vary per machine, so the path is discovered instead of assumed.
#
# Order of preference: an explicit HANDHELD_KIT_SD_MOUNT, then a card
# labelled ROMS - the name emulation front-ends conventionally expect - then
# the writable removable filesystem with the most free space, which on a
# handheld is the games card.
# --------------------------------------------------------------------------
detect_sd_mount() {
    if [ -n "${HANDHELD_KIT_SD_MOUNT:-}" ]; then
        printf '%s\n' "${HANDHELD_KIT_SD_MOUNT%/}"
        return 0
    fi

    local candidate best="" free best_free=0
    for candidate in /run/media/"$SETUP_USER"/*/ /run/media/*/; do
        [ -d "$candidate" ] || continue
        candidate="${candidate%/}"
        mountpoint -q "$candidate" 2>/dev/null || continue
        [ -w "$candidate" ] || continue

        if [ "$(basename "$candidate")" = "ROMS" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi

        free="$(df -BG --output=avail "$candidate" 2>/dev/null | tail -1 | tr -dc '0-9')"
        free="${free:-0}"
        if [ "$free" -gt "$best_free" ]; then
            best="$candidate"
            best_free="$free"
        fi
    done

    [ -n "$best" ] && printf '%s\n' "$best"
    # Always successful: "no card is mounted" is an answer, not a failure, and
    # a non-zero status here would abort the caller under set -e.
    return 0
}

SD_MOUNT="$(detect_sd_mount)"

sd_mounted() {
    [ -n "$SD_MOUNT" ] && mountpoint -q "$SD_MOUNT" 2>/dev/null
}

# --------------------------------------------------------------------------
# The newest Proton-GE build installed, or nothing when there is none.
#
# Two modules need this answer and both must reach the same one: the module
# that sets the default reads the filesystem rather than trusting what the
# module before it believes it installed, and the verification reads it again
# to check the default actually points there.
# --------------------------------------------------------------------------
latest_proton_ge() {
    local candidate candidates=()
    for candidate in "$COMPAT_DIR"/GE-Proton*; do
        [ -d "$candidate" ] && candidates+=("$(basename "$candidate")")
    done
    if [ "${#candidates[@]}" -gt 0 ]; then
        printf '%s\n' "${candidates[@]}" | sort -V | tail -1
    fi
    # "None installed" is an answer, not a failure.
    return 0
}

# --------------------------------------------------------------------------
# Idempotent Flatpak install
# --------------------------------------------------------------------------
# A system-scope Flatpak install is a privileged operation: polkit grants it to
# the session attached to the screen and denies it elsewhere. This function
# copes with both contexts - it uses sudo when a ticket is already available,
# and otherwise falls back to a per-user install, which needs no privileges and
# still lands in an area SteamOS updates leave alone. The fallback is reported
# in the summary rather than applied silently.
flatpak_install() {
    local appid="$1" name="${2:-$1}"
    if flatpak_has "$appid"; then
        log_ok "$name already present"
        record "$name" PRESENT "$appid"
        return 0
    fi

    local command=(flatpak install --system --noninteractive --assumeyes flathub "$appid")
    if [ "$DRY_RUN" != "1" ] && sudo -n true 2>/dev/null; then
        command=(sudo "${command[@]}")
    fi

    if run "installing $name" "${command[@]}"; then
        record "$name" INSTALLED "$appid"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        record "$name" INSTALLED "$appid"
        return 0
    fi

    log_warn "system-scope install not permitted: falling back to a per-user install"

    # Remotes are per scope: the system remote is invisible to a user-scope
    # install, which without its own finds nothing to install from.
    if ! flatpak remotes --user --columns=name 2>/dev/null | grep -qx flathub; then
        run "adding Flathub for this user" \
            flatpak remote-add --if-not-exists --user \
            flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
            || log_warn "adding the user-scope remote failed"
    fi

    if run "installing $name for this user" \
        flatpak install --user --noninteractive --assumeyes flathub "$appid"; then
        record "$name" INSTALLED "$appid (user scope)"
        return 0
    fi

    record "$name" FAILED "$appid"
    return 1
}

# --------------------------------------------------------------------------
# Privileges: one password request, renewed for the duration of the run
# --------------------------------------------------------------------------
SUDO_KEEPALIVE_PID=""

# An attempt, not a requirement. A session with no terminal has no way to
# receive a password, and stopping there would be wrong: nearly every step
# works regardless, and the ones that cannot say so themselves in the summary.
#
# When the graphical launcher is in use it has already primed the sudo
# timestamp, so `sudo -n true` succeeds here and nothing is asked twice.
sudo_begin() {
    [ "$DRY_RUN" = "1" ] && return 0
    if [ "${HANDHELD_KIT_NO_PRIVILEGES:-0}" = "1" ]; then
        log_warn "continuing without administrator rights, as chosen: the steps that need them are skipped"
        return 0
    fi
    if sudo -n true 2>/dev/null; then
        log_info "privileges already available"
    elif [ "$(password_status)" = "unset" ]; then
        # Prompting here would be cruel: nothing the user types can be
        # accepted, so the remedy is named instead.
        log_warn "the account '$SETUP_USER' has no password yet, so the privileged steps cannot run"
        log_warn "set one by running 'passwd' in a terminal, then start this again"
        return 0
    elif [ -t 0 ]; then
        log_step "The password of '$SETUP_USER' is needed for the steps that require privileges"
        sudo -v || { log_warn "password not accepted: continuing without privileges"; return 0; }
    else
        log_warn "no terminal attached: steps that require privileges will be adapted"
        return 0
    fi
    # Renew the ticket while setup.sh is alive, without asking again.
    while true; do
        sudo -n true 2>/dev/null || break
        sleep 50
        kill -0 "$$" 2>/dev/null || break
    done &
    SUDO_KEEPALIVE_PID=$!
    export SUDO_KEEPALIVE_PID
}

sudo_end() {
    [ -n "${SUDO_KEEPALIVE_PID:-}" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    SUDO_KEEPALIVE_PID=""
}

# Whether a privileged step may run. Once the user has declined the password in
# the launcher (HANDHELD_KIT_NO_PRIVILEGES=1) no prompt may appear, so only a
# ticket that already exists counts; otherwise sudo is left to behave as usual.
privileges_allowed() {
    [ "$DRY_RUN" = "1" ] && return 0
    [ "${HANDHELD_KIT_NO_PRIVILEGES:-0}" = "1" ] || return 0
    sudo -n true 2>/dev/null
}

NO_PRIVILEGES_DETAIL="needs administrator rights, which were declined"

# --------------------------------------------------------------------------
# Network
# --------------------------------------------------------------------------
net_available() {
    curl -sSf -o /dev/null -m 8 https://flathub.org/ 2>/dev/null
}

# --------------------------------------------------------------------------
# Verified download: fetch, then compare against the expected sha256.
# A corrupted or substituted archive never reaches its destination.
# --------------------------------------------------------------------------
download_verified() {
    local url="$1" dest="$2" expected_sha="${3:-}"
    local tmp; tmp="$(mktemp)"

    if [ "$DRY_RUN" = "1" ]; then
        printf '  %s[dry run]%s would download %s\n' "$C_YELLOW" "$C_RESET" "$url"
        rm -f "$tmp"
        return 0
    fi

    if ! curl -fsSL --retry 3 --retry-delay 2 -m 600 "$url" -o "$tmp"; then
        log_err "download failed: $url"
        rm -f "$tmp"
        return 1
    fi

    if [ -n "$expected_sha" ]; then
        local actual_sha
        actual_sha="$(sha256sum "$tmp" | cut -d' ' -f1)"
        if [ "$actual_sha" != "$expected_sha" ]; then
            log_err "checksum mismatch for $(basename "$dest")"
            log_err "  expected: $expected_sha"
            log_err "  got:      $actual_sha"
            rm -f "$tmp"
            return 1
        fi
        log_ok "checksum verified: $(basename "$dest")"
    fi

    mkdir -p "$(dirname "$dest")"
    mv "$tmp" "$dest"
}

# --------------------------------------------------------------------------
# The Python vdf module, needed to read and write Steam's configuration files.
#
# SteamOS inherits Arch's PEP 668 EXTERNALLY-MANAGED marker: pip refuses to
# install into the system interpreter, --user included, because pacman owns the
# Python packages there. The route the distribution itself points at is a
# virtual environment, which here lives in the user's home and therefore
# survives system updates. Do not reach for --break-system-packages.
#
# On return PYTHON_VDF holds the interpreter to use.
# --------------------------------------------------------------------------
PYTHON_VDF=""

# The interpreter that already imports vdf, or nothing. It installs nothing, so
# the verification can use it without changing the machine. Should a future
# SteamOS ship the module, the virtual environment becomes redundant and is
# ignored.
find_python_vdf() {
    if python3 -c 'import vdf' 2>/dev/null; then
        command -v python3
    elif [ -x "$VENV_DIR/bin/python" ] && "$VENV_DIR/bin/python" -c 'import vdf' 2>/dev/null; then
        printf '%s\n' "$VENV_DIR/bin/python"
    fi
    return 0
}

ensure_python_vdf() {
    PYTHON_VDF="$(find_python_vdf)"
    if [ -n "$PYTHON_VDF" ]; then
        log_ok "the vdf module is available: $PYTHON_VDF"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        printf '  %s[dry run]%s would create a virtual environment in %s carrying the vdf module\n' \
            "$C_YELLOW" "$C_RESET" "$VENV_DIR"
        return 0
    fi

    if [ ! -x "$VENV_DIR/bin/python" ]; then
        mkdir -p "$(dirname "$VENV_DIR")"
        run "creating the Python virtual environment" python3 -m venv "$VENV_DIR" || return 1
    fi

    run "installing the vdf module into the virtual environment" \
        "$VENV_DIR/bin/python" -m pip install --quiet --disable-pip-version-check vdf || return 1

    if "$VENV_DIR/bin/python" -c 'import vdf' 2>/dev/null; then
        PYTHON_VDF="$VENV_DIR/bin/python"
        log_ok "virtual environment ready"
        return 0
    fi
    log_err "the vdf module is not importable from the virtual environment"
    return 1
}
