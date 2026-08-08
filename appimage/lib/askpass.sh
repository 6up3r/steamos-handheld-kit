#!/usr/bin/env bash
# SUDO_ASKPASS helper: prints a password read from a graphical prompt.
#
# run.sh primes sudo's timestamp once and keeps it alive for the whole run, so
# this helper normally never runs. It exists for the case where that keepalive
# dies and a privileged step is reached with no terminal to type into: without
# it sudo would wait for input that can never arrive, and the run would hang
# with nothing on screen to explain why.

set -u

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/gui.sh"

gui_password "Administrator password" || exit 1
