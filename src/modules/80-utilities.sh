#!/usr/bin/env bash
# Utilities: file synchronisation with a desktop computer.

set -Eeuo pipefail
HANDHELD_KIT_ROOT="${HANDHELD_KIT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$HANDHELD_KIT_ROOT/lib/common.sh"

status=0

log_step "SyncThingy"
flatpak_install com.github.zocker_160.SyncThingy "SyncThingy" || status=1

if flatpak_has com.github.zocker_160.SyncThingy && sd_mounted; then
    # Without explicit access to the mount point the sandbox prevents ROMs from
    # being synchronised: the folders would simply look empty.
    run "access to the memory card for SyncThingy" \
        flatpak override --user --filesystem="$SD_MOUNT" com.github.zocker_160.SyncThingy \
        || log_warn "the memory card grant failed"
fi

record "SyncThingy pairing" MANUAL "pair the handheld with your computer from SyncThingy's interface"

exit "$status"
