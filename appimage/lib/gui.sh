#!/usr/bin/env bash
# Graphical dialogs, on whichever backend the desktop provides.
# Sourced by AppRun, run.sh and askpass.sh; never executed directly.
#
# zenity is preferred over kdialog: both ship with SteamOS, and zenity is the
# one present on the widest range of desktops, so the same code path serves
# every machine this tool is likely to meet. kdialog covers the case where a
# KDE desktop carries no zenity.

[ -n "${GUI_SH_LOADED:-}" ] && return 0
GUI_SH_LOADED=1

GUI_TITLE="SteamOS Handheld Kit"
GUI_BACKEND=""

if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    if command -v zenity >/dev/null 2>&1; then
        GUI_BACKEND=zenity
    elif command -v kdialog >/dev/null 2>&1; then
        GUI_BACKEND=kdialog
    fi
fi

# True when dialogs can actually be drawn.
gui_available() { [ -n "$GUI_BACKEND" ]; }

gui_info() {
    local text="$1"
    case "$GUI_BACKEND" in
        zenity)   zenity  --info --title="$GUI_TITLE" --width=460 --text="$text" >/dev/null 2>&1 ;;
        kdialog)  kdialog --title "$GUI_TITLE" --msgbox "$text" >/dev/null 2>&1 ;;
        *)        printf '%s\n' "$text" ;;
    esac
}

gui_error() {
    local text="$1"
    case "$GUI_BACKEND" in
        zenity)   zenity  --error --title="$GUI_TITLE" --width=460 --text="$text" >/dev/null 2>&1 ;;
        kdialog)  kdialog --title "$GUI_TITLE" --error "$text" >/dev/null 2>&1 ;;
        *)        printf '%s\n' "$text" >&2 ;;
    esac
}

# Exit status 0 means yes.
gui_question() {
    local text="$1"
    case "$GUI_BACKEND" in
        zenity)   zenity  --question --title="$GUI_TITLE" --width=460 --text="$text" >/dev/null 2>&1 ;;
        kdialog)  kdialog --title "$GUI_TITLE" --yesno "$text" >/dev/null 2>&1 ;;
        *)        return 1 ;;
    esac
}

# Reads a password and prints it on standard output. Nothing is echoed to the
# screen, written to a file or passed as a command-line argument.
gui_password() {
    local text="$1"
    case "$GUI_BACKEND" in
        zenity)   zenity  --password --title="$text" 2>/dev/null ;;
        kdialog)  kdialog --title "$GUI_TITLE" --password "$text" 2>/dev/null ;;
        *)        return 1 ;;
    esac
}

# gui_menu <text> <key> <label> <description> [<key> <label> <description> ...]
# Prints the chosen key. A cancelled dialog exits non-zero and prints nothing.
gui_menu() {
    local text="$1"; shift
    local key label description
    local zenity_rows=() kdialog_rows=()

    while [ $# -ge 3 ]; do
        key="$1"; label="$2"; description="$3"; shift 3
        zenity_rows+=("$key" "$label" "$description")
        kdialog_rows+=("$key" "$label - $description")
    done

    case "$GUI_BACKEND" in
        zenity)
            # Column 1 carries the key the caller matches on, and is hidden:
            # what the user reads is the label and the description.
            zenity --list --title="$GUI_TITLE" --text="$text" \
                   --column="key" --column="Action" --column="What it does" \
                   --hide-column=1 --print-column=1 \
                   --width=680 --height=340 \
                   "${zenity_rows[@]}" 2>/dev/null
            ;;
        kdialog)
            kdialog --title "$GUI_TITLE" --menu "$text" "${kdialog_rows[@]}" 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# A pulsating progress window fed with "# message" lines on standard input.
# Used only where no terminal emulator exists to run the setup visibly.
gui_progress() {
    local text="$1"
    case "$GUI_BACKEND" in
        zenity)
            zenity --progress --pulsate --auto-close --no-cancel \
                   --title="$GUI_TITLE" --text="$text" --width=520 >/dev/null 2>&1
            ;;
        *)
            # Without a progress dialog the lines still have somewhere to go,
            # so the caller's pipe never blocks.
            cat >/dev/null
            ;;
    esac
}
