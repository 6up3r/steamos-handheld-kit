# Design decisions

Why these components and not others, and which options were considered and rejected.
[internals.md](internals.md) covers how the result works.

## Principles

**Idempotence.** Every step reads the current state before acting: an installed Flatpak is
skipped, a plugin already at the published version is left alone, a configuration key already
written is not duplicated. A second run is a supported operation, not an accident, because the
intended use includes running it again after every major system update.

**Failures are visible.** `set -Eeuo pipefail` in every script except `appimage/lib/askpass.sh`,
which uses `set -u` alone, and every success message derives from the real exit status of the
step before it. A module that fails does not stop the others: it is recorded and appears in the
summary.

**A per-item summary.** The run ends with one line per component — installed, updated, already
present, skipped, failed, needs you — because a wall of scrolling output is not a report. The
removal ends the same way, and its exit status says whether anything failed to come off.

**Least privilege.** One password request, kept alive for the run. No password appears in the
code, the logs, or a command line. The modules that need no privileges run without them, and
`setup.sh` does not ask at all when every module selected for the run is one of those. A
password declined in the launcher stays declined: the steps that need it are reported as
skipped rather than asked for again.

**Reversibility.** The teardown removes every component of the kinds the setup installs,
including copies that were already present before the kit ran: any app on its Flatpak list,
the whole `~/homebrew` folder with its plugins and themes, and every GE-Proton build. It does
not reset Steam's default compatibility tool, and it does not remove the Flatpak permission
overrides or the user-scope Flathub remote.

**Verification against the running system.** The final module does not re-read what the script
believed it did: it asks systemd, Flatpak, the filesystem and a TCP port. A step that printed
"installed" and produced nothing is caught there.

## Component choices

### No third-party handheld daemon

SteamOS ships `inputplumber.service` with per-model device profiles. It claims the physical
gamepad exclusively and publishes a virtual one that Steam talks to. Installing Handheld Daemon
alongside it puts two daemons in contention for exclusive access to the same HID device. The
module that would have installed one is a verification module instead.

### No TDP or fan plugin

PowerTools and Fantastic are written for Steam Deck hardware and write to registers the vendor
driver already governs on other handhelds. TDP and fan control stay with the native mechanisms,
which the hardware check reports on. On a Steam Deck those plugins are the right tool, so the
warning about them is raised only on hardware that is not one.

### Nothing in the root filesystem

Covered in [internals.md](internals.md): the root filesystem is immutable and A/B, so anything
`pacman` installs disappears at the next update. Flatpak, `~/homebrew` and the home directory
are the three destinations that survive, and they are the only ones the kit writes to itself.
The Decky and Sunshine installers it runs also write under `/etc`.

### Emulation: EmuDeck

Chosen over RetroDECK for its integration of ROMs as individual entries in the Steam library
and for the wider set of emulators it configures. ROMs go on the memory card; the internal
drive stays for Steam games.

### Non-Steam games: Heroic and Lutris

Heroic covers the storefronts — Epic, GOG and Amazon — in one maintained, free client built for
that job. Lutris covers what has no storefront behind it: standalone Windows installers, older
titles, and the community install scripts and runners that go with them. Between them they
reach the games a Steam library does not, and in practice they overlap very little.

Bottles and Junk Store stay excluded: their function is covered by the two above, and each one
added is further surface to maintain.

### Cloud gaming: two different routes

NVIDIA publishes an installer built for SteamOS which adds its own Steam library entry, applies
the official artwork and sets the controller profile. Reproducing that work would be worse than
using it, so GeForce NOW goes through NVIDIA's installer.

Xbox Cloud Gaming has no Linux client at all. The only supported route is a browser in kiosk
mode, and Microsoft documents Edge for exactly this use on handhelds. Unofficial wrappers are
excluded.

The browser needs one non-obvious permission: `--filesystem=/run/udev:ro`. The Gamepad API
reads device metadata from `/run/udev`, and without that access the game streams while the
controller stays inert — a failure that looks like the service's and belongs to the sandbox.

### Proton-GE as the global default

Every Windows game installed afterwards uses it with no manual setting. The choice lives in
`config.vdf`, not in ProtonPlus — ProtonPlus only downloads versions. Titles with a native
Linux build keep using it. A game that misbehaves under Proton-GE, which happens with some
anti-cheat systems, is fixed by assigning it Proton Experimental in its own properties: a
per-title choice always wins over the default.

### Remote access: Sunshine, not Steam's own remote play

The handheld acts as the server and is driven from another computer with a Moonlight client.
The stream is steadier and lower latency, and it does not depend on the Steam client. The
Flatpak package ships the scripts that install its udev rule and register its user service, and
their inverse, which is what the teardown runs.

### The plugin set

| Plugin | Why |
|---|---|
| SteamGridDB | Artwork for non-Steam entries and emulated games, which otherwise show as blank |
| ProtonDB Badges | Community compatibility rating on the game's own page |
| Decky Cloud Save | Cloud saves for non-Steam games, through rclone |
| CSS Loader | Interface themes |
| Storage Cleaner | Reclaims the space shader caches accumulate |
| Battery Tracker | Per-game power consumption |
| HueSync | RGB lighting, on handhelds that have it |

## Packaging decisions

### zenity, with kdialog as the fallback

Both ship with SteamOS. zenity is the one present across the widest range of desktops, so it is
the primary path and the same code serves every machine the tool is likely to meet; kdialog
covers a KDE desktop without zenity. The reasoning behind using a password dialog at all,
rather than `pkexec`, is in [internals.md](internals.md).

### Setting the missing password rather than reporting it

SteamOS ships the user account with no password, and that is precisely the state a first-boot
setup tool meets. Reporting it and stopping would be correct and useless: the machine this tool
exists for is the one that has just been installed.

`passwd` is what sets it, it needs no privileges of its own, and it changes nothing else — so
the launcher offers it rather than sending the user away to a terminal. It is offered only
where this worker has a terminal to type into, because `passwd` reads from one; elsewhere the
dialog names the command instead of pretending to be able to run it.

### A terminal window rather than a progress bar alone

Fifteen minutes of an apparently idle window reads as a crash, and the setup already prints a
readable account of itself. The progress dialog exists as the fallback for a desktop with no
terminal emulator.

### The AppImage carries the source tree unchanged

`build.sh` copies `src/` into the AppDir as it is. What a user runs from the AppImage is byte
for byte what a contributor runs from a checkout, so a bug reproduces the same way in both.

## Nothing is fixed to one machine

The setup runs on any AMD handheld running SteamOS, so every assumption about a particular
unit is a discovered fact instead:

- **The memory card path is discovered.** Both the login name and the card's label vary per
  machine. `detect_sd_mount()` prefers an explicit `HANDHELD_KIT_SD_MOUNT`, then a card
  labelled `ROMS`, then the writable removable filesystem with the most free space.
- **Hardware checks branch on the vendor** the firmware reports, instead of expecting one
  model's kernel modules. TDP controls are looked for at the vendor interface *or* at the
  generic hwmon power cap; the fan interface likewise. An unknown vendor is reported as unknown
  rather than as broken.
- **The controller profile is found through the firmware board name** against the profiles
  installed on the machine, not through a filename fragment belonging to one model. The board
  name comes first because that is the field the profiles actually key on; the product name is
  the fallback.
- **HueSync is installed only where RGB lights exist**, and the verification expects it under
  the same condition.
- **The architecture check refuses anything but x86_64.** The compatibility layer, the plugin
  loader and the emulation front-end are all published for that architecture alone, so
  installing them elsewhere would produce a set of components that cannot run.
- **`jq` is not used.** Every JSON read in the project goes through `python3`, which the
  preflight already requires. A module that parsed a GitHub API response with `jq` would
  depend on a tool nothing declares, and its failure would look like "no pre-release found".
- **GeForce NOW's missing prerequisites are reported as a manual step, not a failure.** They
  belong to NVIDIA's installer, not to this tool, and on a handheld without them the right
  outcome is "this part is yours to do", not a failed run.
- **The teardown asks once, after showing what it removes.** Where there is a terminal to type
  into, that is the typed `REMOVE` after the list, and the launcher adds no question of its own.
  Where there is none, the launcher shows the same list in a dialog and asks there before
  passing `--confirm`, and from the command line a flag that explicit cannot be given by
  accident.
