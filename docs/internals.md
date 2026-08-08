# How it works inside

This page is for people changing the code. It covers the structure, the packaging, and the
details that look arbitrary until you know what they avoid — most of which cost real debugging
on real hardware. [design-decisions.md](design-decisions.md) covers why these components were
chosen; the README covers what the tool does and how a user runs it.

## Layout

```
src/                         the setup logic — this tree runs unchanged from a checkout
  setup.sh                   entry point: flags, module ordering, logging, per-item summary
  teardown.sh                the inverse; removes what setup installs
  VERSION                    the single source of the version number
  lib/common.sh              logging, outcomes, traced execution, state queries, privileges
  lib/preflight.sh           the checks that gate a run
  lib/steam_config.py        writes shortcuts.vdf and config.vdf
  modules/NN-name.sh         one concern each, numbered by dependency order
appimage/                    the graphical wrapper
  AppRun                     entry point of the AppImage: mode, menu, terminal, outcome
  lib/gui.sh                 dialog backend abstraction (zenity, kdialog)
  lib/run.sh                 the worker: privileges, run, record the outcome
  lib/askpass.sh             SUDO_ASKPASS helper
  make-icon.py               draws the icon at build time
  *.desktop                  the menu entry the AppImage carries
build.sh                     source checks, AppDir assembly, packing
.github/workflows/build.yml  the same build, plus the release on a tag
```

`setup.sh` iterates over `modules/*.sh` in filename order, so the numeric prefix *is* the
dependency order and there is no second list to keep in step with it. Each module runs in its
own process: one that fails is recorded and the others still run. Each module also sources
`lib/common.sh` itself, so any of them can be run on its own with `--only`.

The version lives in `src/VERSION` and nowhere else. `common.sh` reads it at runtime,
`build.sh` reads it for the output filename, and the workflow refuses to publish a tag that
disagrees with it.

## The ground rules of the platform

### SteamOS is immutable, and that shapes everything

The root filesystem is read-only and there are two of them. A system update writes the inactive
partition and reboots into it, so anything installed with `pacman` is gone at the next update —
silently, and long after whoever installed it has forgotten. Three destinations survive:
`/var/lib/flatpak`, `~/homebrew` (Decky), and the user's home directory. Every module writes to
one of those three and to nothing else. The read-only root is never disabled.

### Flatpak system scope needs polkit

`flatpak install --system` is privileged, and polkit grants it to the session attached to the
screen while denying it to a remote shell. `flatpak_install()` in `common.sh` therefore tries
the system scope with `sudo` when a ticket already exists, and falls back to `--user` when that
fails. The fallback has a trap of its own: remotes are per scope, so a user-scope install finds
nothing until the user-scope Flathub remote is added. Both paths are in the installer, and the
fallback appears in the summary rather than happening silently.

### PEP 668 blocks pip

SteamOS inherits Arch's `EXTERNALLY-MANAGED` marker, so `pip install --user` refuses. The route
the distribution itself points at is a virtual environment, and `ensure_python_vdf()` builds
one under `~/.local/share/steamos-handheld-kit/venv`. Do not reach for
`--break-system-packages`: it works until the next update rewrites the system Python.

### Steam rewrites its own configuration on exit

`shortcuts.vdf` (binary) and `config.vdf` (text) are read when Steam starts and written back
from memory when it exits. Editing them while Steam runs loses the edit with **no error at
all**. Every write is therefore gathered in `88-steam-config.sh`, which stops Steam, writes,
and starts it again.

Starting it again matters as much as stopping it. Steam has to be handed to the user's session
manager with `systemd-run --user --collect --unit=<name> steam`. Started as a child of the
calling shell — `nohup steam &` — it attaches to that session, exits shortly after, and leaves
the handheld with its physical gamepad claimed by the controller service and no virtual one in
its place: a handheld with no controller. When the session variables are missing, as they are
over SSH, the module reads them out of `/proc/<pid>/environ` of the running desktop.

The global default compatibility tool is `CompatToolMapping."0"` in `config.vdf`. Only that key
is touched; per-title choices belong to the user.

### Decky Loader is the fragile part

- Plugins are served from a store API that indexes them **by hash**, and that hash is the
  archive's SHA-256. One value is both the address and the integrity check, which is why
  `download_verified` is called with it.
- A plugin's installed version lives in its own `package.json`. Read that, not a marker file
  this tool wrote — otherwise a plugin the user installed from Decky's own store looks absent
  and gets overwritten.
- The frontend injects itself into Steam's interface through internal APIs that Valve renames
  without notice. When that happens the script is injected but dies before creating
  `window.DeckyPluginLoader`: the service is active, the plugins are loaded, the logs are
  clean, and there is **no icon**. The failure lives in Steam's JavaScript engine, where the
  Python log cannot see it.
- Diagnose it through Steam's CEF debug port, `127.0.0.1:8080`, context `SharedJSContext`:
  `window.DeckyPluginLoader` exists only after a successful initialisation. A lone
  `window.deckyHasLoaded` means the injection arrived and stopped.
- The fix ships in pre-releases, and applying it takes **two inseparable steps**: replace the
  binary *and* set `branch: 1` in `homebrew/settings/loader.json`, with the service stopped.
  Change only the binary and Decky's own updater restores the configured channel within minutes
  — it looks like it worked and then undoes itself.
- The project's `install_prerelease.sh` is not used: it exits 1 on this platform, and it begins
  by deleting `~/homebrew/services`, so a failure leaves Decky dismantled rather than
  unchanged. Replacing the binary reaches the same end without touching anything else, because
  the systemd unit already points at that path and pre-releases do not move it.

### Third-party installers and their quirks

- **EmuDeck**: its `install.sh` detects SteamOS and skips the dependency stage that would run
  `pacman`, so it is safe as-is. It ends by launching a GUI configurator, which an unattended
  installer must not wait on — `60-emulation.sh` therefore does what the installer does up to
  that point and leaves the launch to the user.
- **GeForce NOW**: NVIDIA's SteamOS installer asks for consent through `kdialog` as its very
  first action, and **exits 0 without installing anything** when that dialog cannot be drawn. A
  headless run must treat that as "not done": `85-cloud-gaming.sh` checks the real effect — the
  entry appearing in `shortcuts.vdf` — rather than the exit status.
- **Sunshine**: install the Flatpak, then run its bundled `additional-install.sh`, which adds
  the udev rule and registers the user service `app-dev.lizardbyte.app.Sunshine.service`. The
  rule carries `TAG+="uaccess"`, which grants `/dev/uinput` to the active session by ACL — no
  group membership, no reboot. So the module tests whether `/dev/uinput` is writable, not
  whether a group exists. Note the Flatpak build has no KMS capture, which limits capture under
  gamescope.

### InputPlumber profiles key on the board name

A device profile under `/usr/share/inputplumber/devices/` declares the machines it covers with
a `matches:` block naming DMI fields, and the field it uses is `board_name` together with
`sys_vendor` — not `product_name`. The two are not interchangeable: a product name carries
marketing text and can repeat the board code inside itself, so searching the profiles for it
finds nothing and the check reports a machine with a perfectly good profile as unmatched.
`10-hardware-check.sh` therefore searches for the board name first and falls back to the
product name, skipping any value shorter than four characters because a short one matches half
the directory by accident.

### Three traps that cost time

- The handheld suspends itself after a few minutes of inactivity, killing long downloads.
  `systemd-inhibit` is the remedy, but the permission is granted only to the session on the
  screen — so `setup.sh` re-executes itself under the inhibitor when it can and continues with
  a warning when it cannot. An accessory safeguard must never be a precondition for starting.
- A process name is not a reliable readiness signal during startup: Steam's launcher and its
  real binary carry different names, so a name check reports absent mid-transition. Wait for an
  observable effect instead — which is why the restart waits for the virtual gamepad to
  reappear.
- A shell function that *detects* something must return success. Under `set -e`, a function
  returning non-zero from an unguarded call aborts the script — which turns a verification
  routine that should list every problem into one that stops at the first. `inspect()` in
  `90-verify.sh` and `detect_sd_mount()` in `common.sh` both end with an explicit success for
  this reason.

## The AppImage

### Why a graphical password prompt, and not pkexec

The run needs privileges in a handful of places — installing the plugin loader, copying plugins
into `~/homebrew`, managing its service. From a double-clicked application there is no terminal
for `sudo` to read a password from, so it has to come from a dialog.

`pkexec` was the obvious candidate and was rejected. It authorises one command at a time and
retains the authorisation for a few minutes; a run that spends twenty of them downloading would
therefore ask again partway through, at a moment nobody chose, quite possibly while the user
has walked away. It also sanitises the environment in ways the third-party installers this tool
runs do not expect.

What ships instead: one `zenity --password` dialog, piped into `sudo -S -v`, which primes
sudo's timestamp; `sudo_begin()` in `common.sh` then refreshes it every fifty seconds for as
long as the run lives, so every later `sudo` is non-interactive. The password exists only as a
shell variable in `run.sh`: never on disk, never in the log, never in a command line where the
process list would show it.

**Where that prompt happens is not incidental.** sudo binds its timestamp to the terminal that
created it. A password collected by `AppRun` and used inside the terminal window `AppRun` opens
would be invisible there, and every privileged step would ask again or fail. So `run.sh` — the
worker that executes inside that window — is what asks. `askpass.sh` is the safety net: if the
keepalive ever dies and a privileged step is reached with no terminal, sudo calls it and the
user sees a dialog instead of a run that hangs with nothing on screen.

### A first boot has no password at all

The user account SteamOS ships has no password, and in that state `sudo` rejects everything
typed at it — so the naive flow gives three refused password dialogs and no explanation. The
state is readable without privileges: `passwd -S <user>` reports its own account's status to
its owner, `P` for a usable password, `L` for a locked one, `NP` for none. `password_status()`
in `common.sh` maps those three onto `set`, `unset` and `unknown`, and an unreadable answer is
`unknown` rather than `unset` so a failed probe never blocks a machine that was fine.

Both layers read it. `sudo_begin()` names the remedy instead of prompting into a wall.
`run.sh`, which has a terminal, offers to run `passwd` right there and then hands the same
window straight to `sudo -v`, rather than bouncing the user to a dialog two seconds after they
finished typing into the terminal. Nothing keeps the plaintext around to reuse — inventing
somewhere to keep it would be the wrong trade — so the password is typed three times in all,
but in one place. A refusal there is not fatal: `acquire_privileges` runs immediately
afterwards and asks in its own way.

### Why a terminal window, and not only a progress bar

A window that appears to do nothing for fifteen minutes while a gigabyte downloads reads as a
crash. The setup already prints a well-structured account of itself, so `AppRun` opens a
terminal emulator and runs it there, visibly. It tries `konsole`, `ptyxis`, `gnome-terminal`,
`xfce4-terminal`, `alacritty`, `kitty`, `xterm`, in that order — SteamOS ships the first.

Several of those hand the request to a daemon and return immediately, so the launcher cannot
wait on the terminal's exit status. `run.sh` instead writes two files into a temporary
directory: `started` when it begins, `status` when it ends. `AppRun` waits for the first for
thirty seconds — long enough for any window to appear — and falls back to a progress dialog if
it never arrives, then waits for the second however long the run takes. `started` is created
under `noclobber`, so if the terminal was merely slow and both paths start a worker, exactly
one of them wins and the other exits.

### FUSE

An AppImage mounts itself with FUSE. SteamOS provides it — `/dev/fuse` exists and `fusermount`
is installed — and the tool has been run from an AppImage on that machine. Where it is absent,
the AppImage runtime prints an explanation and suggests `--appimage-extract-and-run`, but it
prints it on standard error, which a double click discards. There is no way to draw a dialog
from inside a file that could not be opened, so the README's troubleshooting section carries
the answer instead: open a terminal, run it there, read the message.

### The icon

`appimage/make-icon.py` draws it at build time from distance functions, with only the standard
library, and nothing binary is committed. The build regenerates it every time, so the icon that
ships is always the output of code somebody can read.

## Building

`./build.sh` does five things, in this order: parses every shell script and compiles the Python
(and runs `shellcheck` when it is installed), assembles the AppDir, draws the icon and
validates the `.desktop` entry, fetches `appimagetool` and checks it against a pinned SHA-256,
then packs the image and writes `dist/SHA256SUMS`.

The pin matters more than it looks. Upstream has republished the assets of an existing tag
before — the binary behind tag `1.9.1` reports itself as a later continuous build — so without
a checksum the packaging tool could change under the project without a trace. With one, that
becomes a loud build failure. `APPIMAGETOOL_SHA256` and `APPIMAGETOOL` exist to unblock a build
deliberately once the change has been looked at.

`.github/workflows/build.yml` runs the same script on every push and pull request. On a `v*`
tag it additionally checks the tag against `src/VERSION`, unpacks the built image and asks it
for its version — a mis-assembled AppDir fails there rather than on a user's machine — and then
creates the release with the AppImage, the checksum file and the matching CHANGELOG section as
its notes.

## Known gaps

- No AppStream metainfo file ships in the AppDir, so `appimagetool` is run with
  `--no-appstream`. An AppStream ID is meant to be a reverse-DNS name tied to a domain the
  project controls, and this project has none to claim.
- The fallbacks for a desktop with no terminal emulator, and for one with `kdialog` but no
  `zenity`, are written but have not been exercised: SteamOS provides both.
