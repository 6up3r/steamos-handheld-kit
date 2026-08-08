#!/usr/bin/env bash
# Builds the AppImage.
#
# Runs on any x86_64 Linux with bash, python3, curl and coreutils. The only
# external tool it needs is appimagetool, which it downloads once into .tools/
# and verifies against a pinned checksum before running.
#
#   ./build.sh                 build into dist/
#   APPIMAGETOOL=/path/to/it ./build.sh    use a copy already on this machine

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

VERSION="$(cat src/VERSION)"
ARCH="${ARCH:-x86_64}"
BUILD_DIR="$REPO_ROOT/build"
APPDIR="$BUILD_DIR/AppDir"
DIST_DIR="$REPO_ROOT/dist"
TOOLS_DIR="$REPO_ROOT/.tools"
OUTPUT="$DIST_DIR/SteamOS-Handheld-Kit-$VERSION-$ARCH.AppImage"

# appimagetool is pinned by version and by checksum. Upstream has republished
# the assets of an existing tag before, so the checksum is what makes such a
# substitution a loud build failure instead of a silent change of tooling.
APPIMAGETOOL_VERSION="1.9.1"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/$APPIMAGETOOL_VERSION/appimagetool-$ARCH.AppImage"
APPIMAGETOOL_SHA256="${APPIMAGETOOL_SHA256:-ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0}"

step() { printf '\n\033[1;36m>> %s\033[0m\n' "$*"; }
info() { printf '   %s\n' "$*"; }
die()  { printf '\n\033[31mBuild failed: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
step "Checking the sources"
# ---------------------------------------------------------------------------
shell_scripts=(
    src/setup.sh
    src/teardown.sh
    src/lib/common.sh
    src/lib/preflight.sh
    appimage/AppRun
    appimage/lib/gui.sh
    appimage/lib/run.sh
    appimage/lib/askpass.sh
    build.sh
)
while IFS= read -r module; do
    shell_scripts+=("$module")
done < <(find src/modules -name '*.sh' | sort)

for script in "${shell_scripts[@]}"; do
    bash -n "$script" || die "syntax error in $script"
done
info "${#shell_scripts[@]} shell scripts parse"

python3 -m py_compile src/lib/steam_config.py appimage/make-icon.py \
    || die "a Python file does not compile"
find . -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
info "2 Python files compile"

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck --severity=warning "${shell_scripts[@]}" || die "shellcheck reported warnings"
    info "shellcheck is clean"
else
    info "shellcheck is not installed: skipping that check"
fi

# ---------------------------------------------------------------------------
step "Assembling the AppDir"
# ---------------------------------------------------------------------------
rm -rf "$BUILD_DIR"
mkdir -p "$APPDIR/usr/lib"

# The setup itself, unchanged: what runs from the AppImage is the same tree a
# contributor runs from a checkout.
cp -a src/. "$APPDIR/usr/lib/steamos-handheld-kit/"

# The graphical launcher that wraps it.
mkdir -p "$APPDIR/usr/lib/launcher"
cp -a appimage/lib/. "$APPDIR/usr/lib/launcher/"
cp appimage/AppRun "$APPDIR/AppRun"
cp appimage/steamos-handheld-kit.desktop "$APPDIR/steamos-handheld-kit.desktop"

chmod +x "$APPDIR/AppRun" \
         "$APPDIR/usr/lib/launcher/run.sh" \
         "$APPDIR/usr/lib/launcher/askpass.sh" \
         "$APPDIR/usr/lib/steamos-handheld-kit/setup.sh" \
         "$APPDIR/usr/lib/steamos-handheld-kit/teardown.sh"
chmod +x "$APPDIR/usr/lib/steamos-handheld-kit/modules/"*.sh
info "payload: $(find "$APPDIR" -type f | wc -l) files"

# ---------------------------------------------------------------------------
step "Drawing the icon"
# ---------------------------------------------------------------------------
python3 appimage/make-icon.py "$APPDIR/steamos-handheld-kit.png" 256 \
    || die "the icon could not be drawn"
# AppImage thumbnailers read .DirIcon; desktop menus read the file the .desktop
# entry names. Both have to be there.
cp "$APPDIR/steamos-handheld-kit.png" "$APPDIR/.DirIcon"

if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$APPDIR/steamos-handheld-kit.desktop" \
        || die "the .desktop entry is not valid"
    info "the .desktop entry validates"
else
    info "desktop-file-validate is not installed: skipping that check"
fi

# ---------------------------------------------------------------------------
step "Fetching appimagetool"
# ---------------------------------------------------------------------------
if [ -n "${APPIMAGETOOL:-}" ]; then
    info "using the copy given in APPIMAGETOOL: $APPIMAGETOOL"
    [ -x "$APPIMAGETOOL" ] || die "$APPIMAGETOOL is not executable"
else
    APPIMAGETOOL="$TOOLS_DIR/appimagetool-$APPIMAGETOOL_VERSION-$ARCH.AppImage"
    if [ ! -f "$APPIMAGETOOL" ]; then
        mkdir -p "$TOOLS_DIR"
        info "downloading appimagetool $APPIMAGETOOL_VERSION"
        curl -fsSL --retry 3 --retry-delay 2 "$APPIMAGETOOL_URL" -o "$APPIMAGETOOL.part" \
            || die "appimagetool could not be downloaded"
        mv "$APPIMAGETOOL.part" "$APPIMAGETOOL"
    fi

    actual="$(sha256sum "$APPIMAGETOOL" | cut -d' ' -f1)"
    if [ "$actual" != "$APPIMAGETOOL_SHA256" ]; then
        rm -f "$APPIMAGETOOL"
        die "appimagetool checksum mismatch
   expected: $APPIMAGETOOL_SHA256
   got:      $actual
   Upstream has replaced this asset. Check what changed, then set
   APPIMAGETOOL_SHA256 to the new value or point APPIMAGETOOL at a trusted copy."
    fi
    chmod +x "$APPIMAGETOOL"
    info "checksum verified"
fi

# ---------------------------------------------------------------------------
step "Packing the AppImage"
# ---------------------------------------------------------------------------
mkdir -p "$DIST_DIR"
rm -f "$OUTPUT"

# --appimage-extract-and-run: appimagetool is itself an AppImage, and build
# machines - CI containers above all - frequently have no FUSE. Unpacking it
# first works everywhere and changes nothing about the result.
if ! ARCH="$ARCH" "$APPIMAGETOOL" --appimage-extract-and-run \
        --no-appstream "$APPDIR" "$OUTPUT"; then
    die "appimagetool could not build the image"
fi

[ -f "$OUTPUT" ] || die "appimagetool reported success but produced no file"
chmod +x "$OUTPUT"

( cd "$DIST_DIR" && sha256sum "$(basename "$OUTPUT")" > SHA256SUMS )

# ---------------------------------------------------------------------------
step "Done"
# ---------------------------------------------------------------------------
info "$OUTPUT"
info "$(du -h "$OUTPUT" | cut -f1) - $(cut -d' ' -f1 < "$DIST_DIR/SHA256SUMS")"
