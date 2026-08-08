#!/usr/bin/env bash
# ProtonPlus and the latest Proton-GE release.
#
# The release publishes two archives: one for x86_64 and one carrying an
# "-aarch64" suffix for ARM. Downloading the second one here would produce a
# compatibility tool Steam lists but cannot launch, so the architecture filter
# is not a detail.

set -Eeuo pipefail
HANDHELD_KIT_ROOT="${HANDHELD_KIT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$HANDHELD_KIT_ROOT/lib/common.sh"

status=0
PROTON_GE_API="https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest"

# ---------------------------------------------------------------------------
# ProtonPlus: a graphical version manager, for the updates that come later
# ---------------------------------------------------------------------------
log_step "ProtonPlus"
flatpak_install com.vysp3r.ProtonPlus "ProtonPlus" || status=1

# ProtonPlus lives in a sandbox and must be able to write where Steam reads its
# compatibility tools, or it shows the list and installs nothing.
if flatpak_has com.vysp3r.ProtonPlus; then
    run "granting ProtonPlus access to ~/.steam" \
        flatpak override --user --filesystem="$HOME/.steam" com.vysp3r.ProtonPlus \
        || log_warn "setting the permission failed"
fi

# ---------------------------------------------------------------------------
# Proton-GE
# ---------------------------------------------------------------------------
log_step "Proton-GE"

if [ "$DRY_RUN" = "1" ]; then
    printf '  %s[dry run]%s would query %s and install the latest x86_64 release\n' \
        "$C_YELLOW" "$C_RESET" "$PROTON_GE_API"
    exit 0
fi

metadata="${TMPDIR:-/tmp}/proton-ge-release.json"
trap 'rm -f "$metadata"' EXIT
if ! curl -fsSL -m 60 "$PROTON_GE_API" -o "$metadata"; then
    log_err "the Proton-GE releases cannot be queried"
    record "Proton-GE" FAILED "GitHub API unreachable"
    exit 1
fi

# Extracts the tag, the x86_64 archive URL and the checksum file URL.
read_release() {
    python3 - "$metadata" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
tag = data.get('tag_name', '')
archive = checksums = ''
for asset in data.get('assets', []):
    name = asset['name']
    if 'aarch64' in name:
        continue
    if name.endswith('.tar.gz'):
        archive = asset['browser_download_url']
    elif name.endswith('.sha512sum'):
        checksums = asset['browser_download_url']
print(tag)
print(archive)
print(checksums)
PY
}

mapfile -t fields < <(read_release)
tag="${fields[0]:-}"
archive_url="${fields[1]:-}"
checksums_url="${fields[2]:-}"

if [ -z "$tag" ] || [ -z "$archive_url" ]; then
    log_err "the release cannot be read: no x86_64 archive identified"
    record "Proton-GE" FAILED "asset not identified"
    exit 1
fi

log_info "latest release: $tag"

mkdir -p "$COMPAT_DIR"

if [ -d "$COMPAT_DIR/$tag" ]; then
    log_ok "$tag already present"
    record "Proton-GE" PRESENT "$tag"
    exit "$status"
fi

archive="${TMPDIR:-/tmp}/$tag.tar.gz"
log_info "downloading $tag (around 400 MB, this takes a few minutes)"
if ! curl -fL --retry 3 --retry-delay 2 -m 1800 "$archive_url" -o "$archive"; then
    log_err "download failed"
    record "Proton-GE" FAILED "download failed"
    exit 1
fi

# Checksum verification: a truncated archive extracts halfway and produces a
# compatibility tool that fails when the first game starts.
if [ -n "$checksums_url" ]; then
    if curl -fsSL -m 60 "$checksums_url" -o "${archive}.sha512sum"; then
        expected="$(cut -d' ' -f1 < "${archive}.sha512sum")"
        actual="$(sha512sum "$archive" | cut -d' ' -f1)"
        if [ "$expected" != "$actual" ]; then
            log_err "checksum mismatch: archive discarded"
            rm -f "$archive" "${archive}.sha512sum"
            record "Proton-GE" FAILED "invalid checksum"
            exit 1
        fi
        log_ok "checksum verified"
    else
        log_warn "the checksum file cannot be downloaded: continuing without verification"
    fi
else
    log_warn "this release publishes no checksums: continuing without verification"
fi

if run "extracting into $COMPAT_DIR" tar -xzf "$archive" -C "$COMPAT_DIR"; then
    if [ -d "$COMPAT_DIR/$tag" ]; then
        log_ok "$tag installed"
        record "Proton-GE" INSTALLED "$tag"
    else
        log_err "extraction finished but the $tag directory does not exist"
        record "Proton-GE" FAILED "unexpected archive layout"
        status=1
    fi
else
    record "Proton-GE" FAILED "extraction failed"
    status=1
fi

rm -f "$archive" "${archive}.sha512sum"

exit "$status"
