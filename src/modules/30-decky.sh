#!/usr/bin/env bash
# Decky Loader and its plugins.
#
# Plugins are installed by querying the store index: for every version the
# index exposes a "hash" field that is at once the archive's address on the CDN
# and its SHA-256. One value therefore serves as both coordinate and integrity
# check, and a download that does not match its own address is discarded.

set -Eeuo pipefail
HANDHELD_KIT_ROOT="${HANDHELD_KIT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$HANDHELD_KIT_ROOT/lib/common.sh"

status=0

# Which channel to install.
#
# Decky's frontend grafts itself onto Steam's user interface through Steam's
# internal APIs, which Valve renames without notice. When that happens the
# stable build is injected but dies before it can build its own interface, and
# the icon never appears even though nothing logs an error - the failure lives
# in Steam's JavaScript engine, where the Python service log cannot reach.
#
# Pre-releases carry the adaptation to the renamed APIs. With
# HANDHELD_KIT_DECKY_CHANNEL=prerelease this module installs the base with
# the official installer and then replaces the loader binary alone.
#
# Why not the project's own pre-release installer: install_prerelease.sh exits
# 1 on this platform, and it begins by deleting ~/homebrew/services - so a
# failure leaves Decky dismantled rather than merely unchanged. Replacing the
# binary reaches the same end without touching anything else: the systemd unit
# already installed points at that path, and pre-releases do not move it.
CHANNEL="${HANDHELD_KIT_DECKY_CHANNEL:-stable}"
DECKY_INSTALLER="https://github.com/SteamDeckHomebrew/decky-installer/releases/latest/download/install_release.sh"
DECKY_API="https://api.github.com/repos/SteamDeckHomebrew/decky-loader/releases?per_page=10"
STORE_INDEX="https://plugins.deckbrew.xyz/plugins"
CDN_BASE="https://cdn.tzatzikiweeb.moe/file/steam-deck-homebrew/versions"

PLUGINS=(
    "SteamGridDB"
    "ProtonDB Badges"
    "Decky Cloud Save"
    "CSS Loader"
    "Storage Cleaner"
    "Battery Tracker"
)

# HueSync drives the RGB rings around the sticks. It is only worth installing
# where such lights exist, which the kernel reports as an RGB LED device.
if compgen -G "/sys/class/leds/*rgb*" >/dev/null 2>&1; then
    PLUGINS+=("HueSync")
fi

# ---------------------------------------------------------------------------
# Decky Loader
# ---------------------------------------------------------------------------
log_step "Decky Loader (channel: $CHANNEL)"

decky_installed() { [ -x "$DECKY_DIR/services/PluginLoader" ]; }

# Recent builds record their version in services/.loader.version.
decky_version() { cat "$DECKY_DIR/services/.loader.version" 2>/dev/null || echo 'unknown'; }

if decky_installed && systemctl is-active --quiet plugin_loader 2>/dev/null; then
    version="$(decky_version)"
    log_ok "already installed and running (version $version)"
    record "Decky Loader" PRESENT "version $version"
else
    # The official installer also repairs an existing installation whose
    # systemd unit a SteamOS update has overwritten.
    if decky_installed; then
        log_warn "present but the service is not active: repairing"
    fi
    installer_tmp="${TMPDIR:-/tmp}/decky-install.sh"
    if download_verified "$DECKY_INSTALLER" "$installer_tmp" ""; then
        if run_visible "running the Decky installer" sudo -E bash "$installer_tmp"; then
            log_ok_done "Decky Loader installed"
            record "Decky Loader" INSTALLED ""
        else
            log_err "the Decky installer failed"
            record "Decky Loader" FAILED "installer ended with an error"
            exit 1
        fi
        rm -f "$installer_tmp"
    else
        record "Decky Loader" FAILED "installer download failed"
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Pre-release channel
#
# This has two inseparable parts: the binary AND the channel preference.
# Decky's own updater restores whatever the configured channel says, so
# replacing only the executable makes it revert within minutes - it looks like
# it worked and then undoes itself.
#
# The service is stopped before either file is touched: while running, Decky
# notices the substitution and reverses it.
# ---------------------------------------------------------------------------
if [ "$CHANNEL" = "prerelease" ] && [ "$DRY_RUN" != "1" ]; then
    log_step "Switching to the pre-release channel"

    releases_json="${TMPDIR:-/tmp}/decky-releases.json"
    tag=""
    url=""
    if curl -fsSL -m 30 "$DECKY_API" -o "$releases_json"; then
        mapfile -t fields < <(python3 - "$releases_json" <<'PY'
import json, sys
tag = url = ''
for release in json.load(open(sys.argv[1], encoding='utf-8')):
    if release.get('prerelease'):
        tag = release.get('tag_name', '')
        for asset in release.get('assets', []):
            if asset['name'].endswith('PluginLoader'):
                url = asset['browser_download_url']
                break
        break
print(tag)
print(url)
PY
)
        tag="${fields[0]:-}"
        url="${fields[1]:-}"
    fi
    rm -f "$releases_json"

    installed_version="$(cat "$DECKY_DIR/services/.loader.version" 2>/dev/null || echo '?')"

    if [ -z "$tag" ] || [ -z "$url" ]; then
        log_err "no pre-release found"
        record "Decky pre-release" FAILED "release not identified"
        status=1
    elif [ "$installed_version" = "$tag" ]; then
        log_ok "already on pre-release $tag"
        record "Decky pre-release" PRESENT "$tag"
    else
        log_info "latest pre-release: $tag (installed: $installed_version)"
        if download_verified "$url" "${TMPDIR:-/tmp}/PluginLoader.pre" ""; then
            chmod +x "${TMPDIR:-/tmp}/PluginLoader.pre"
            cat > "${TMPDIR:-/tmp}/decky-channel.sh" <<SCRIPT
#!/usr/bin/env bash
set -e
systemctl stop plugin_loader
cp "${TMPDIR:-/tmp}/PluginLoader.pre" "$DECKY_DIR/services/PluginLoader"
chmod +x "$DECKY_DIR/services/PluginLoader"
chown root:root "$DECKY_DIR/services/PluginLoader"
echo "$tag" > "$DECKY_DIR/services/.loader.version"
python3 -c "
import json
path = '$DECKY_DIR/settings/loader.json'
settings = json.load(open(path))
settings['branch'] = 1
json.dump(settings, open(path, 'w'), indent=4)
"
systemctl start plugin_loader
SCRIPT
            if run "installing pre-release $tag" sudo bash "${TMPDIR:-/tmp}/decky-channel.sh"; then
                sleep 4
                if systemctl is-active --quiet plugin_loader; then
                    log_ok "pre-release $tag active, channel set to pre-release"
                    record "Decky pre-release" INSTALLED "$tag"
                else
                    log_err "the service does not come back after the channel change"
                    record "Decky pre-release" FAILED "service inactive"
                    status=1
                fi
            else
                record "Decky pre-release" FAILED "substitution failed"
                status=1
            fi
            rm -f "${TMPDIR:-/tmp}/PluginLoader.pre" "${TMPDIR:-/tmp}/decky-channel.sh"
        else
            record "Decky pre-release" FAILED "download failed"
            status=1
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Store index, downloaded once for every plugin
# ---------------------------------------------------------------------------
log_step "Plugin index"
INDEX="${TMPDIR:-/tmp}/decky-store.json"
# The index is only needed for the lifetime of this module: it is removed on
# exit whatever the outcome.
trap 'rm -f "$INDEX"' EXIT
if [ "$DRY_RUN" = "1" ]; then
    log_info "[dry run] would download the index from $STORE_INDEX"
else
    if curl -fsSL -m 60 "$STORE_INDEX" -o "$INDEX"; then
        total="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$INDEX" 2>/dev/null || echo '?')"
        log_ok "index downloaded: $total plugins available"
    else
        log_err "the store index is unreachable: no plugin will be installed"
        record "Decky plugin index" FAILED "$STORE_INDEX"
        exit 1
    fi
fi

# Prints "<version> <hash>" for the requested plugin.
resolve_plugin() {
    python3 - "$INDEX" "$1" <<'PY'
import json, sys
index, wanted = sys.argv[1], sys.argv[2].lower()
for plugin in json.load(open(index, encoding='utf-8')):
    if plugin.get('name', '').lower() == wanted:
        versions = plugin.get('versions') or []
        if versions:
            print(versions[0]['name'], versions[0]['hash'])
            sys.exit(0)
sys.exit(1)
PY
}

# ---------------------------------------------------------------------------
# Plugins
# ---------------------------------------------------------------------------
mkdir -p "$DECKY_DIR/plugins" 2>/dev/null || true
plugins_changed=0

for name in "${PLUGINS[@]}"; do
    log_step "Plugin: $name"

    if [ "$DRY_RUN" = "1" ]; then
        printf '  %s[dry run]%s would resolve and install "%s"\n' "$C_YELLOW" "$C_RESET" "$name"
        continue
    fi

    if ! entry="$(resolve_plugin "$name")"; then
        log_err "not found in the store index"
        record "$name" FAILED "absent from the index"
        status=1
        continue
    fi
    version="${entry%% *}"
    hash="${entry##* }"

    # The plugin directory carries the exact name the store uses.
    plugin_dir="$DECKY_DIR/plugins/$name"
    marker="$plugin_dir/.installed-version"

    # The installed version is read from the plugin's own package.json, which
    # exists however it was installed - by this module or from Decky's store.
    # Trusting only the marker this module writes would make a plugin the user
    # installed look absent, and overwrite it.
    installed=""
    if [ -f "$plugin_dir/package.json" ]; then
        installed="$(python3 -c "
import json,sys
try: print(json.load(open('$plugin_dir/package.json')).get('version') or '')
except Exception: print('')
" 2>/dev/null)"
    fi
    [ -z "$installed" ] && installed="$(cat "$marker" 2>/dev/null || echo '')"

    if [ -n "$installed" ] && [ "${installed#v}" = "${version#v}" ]; then
        log_ok "already at version $installed"
        record "$name" PRESENT "version $installed"
        continue
    fi
    if [ -n "$installed" ]; then
        log_info "installed $installed, available $version"
    fi

    archive="${TMPDIR:-/tmp}/decky-plugin-$hash.zip"
    if ! download_verified "$CDN_BASE/$hash.zip" "$archive" "$hash"; then
        record "$name" FAILED "download or checksum invalid"
        status=1
        continue
    fi

    # Extraction into a staging area: a malformed archive leaves the already
    # installed directory intact.
    staging="$(mktemp -d)"
    if ! unzip -q -o "$archive" -d "$staging"; then
        log_err "the archive cannot be extracted"
        record "$name" FAILED "corrupted archive"
        rm -rf "$staging" "$archive"
        status=1
        continue
    fi

    inner="$(find "$staging" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [ -z "$inner" ] && inner="$staging"

    if [ -d "$plugin_dir" ]; then
        sudo rm -rf "$plugin_dir"
    fi
    if sudo cp -r "$inner" "$plugin_dir" && sudo chown -R "$SETUP_USER:$SETUP_USER" "$plugin_dir"; then
        echo "$version" > "$marker"
        log_ok "installed: version $version"
        record "$name" INSTALLED "version $version"
        plugins_changed=$((plugins_changed + 1))
    else
        log_err "copying into the plugins directory failed"
        record "$name" FAILED "copy failed"
        status=1
    fi

    rm -rf "$staging" "$archive"
done

# ---------------------------------------------------------------------------
# Reload: freshly copied plugins are read only when the service restarts
# ---------------------------------------------------------------------------
if [ "$plugins_changed" -gt 0 ]; then
    log_step "Reloading Decky"
    if run "restarting the plugin_loader service" sudo systemctl restart plugin_loader; then
        sleep 3
        if systemctl is-active --quiet plugin_loader; then
            log_ok "service restarted and active"
        else
            log_err "the service is not active after the restart"
            status=1
        fi
    else
        status=1
    fi
fi

exit "$status"
