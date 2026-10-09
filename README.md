# SteamOS Handheld Kit

A single file you double-click on a freshly installed SteamOS handheld to turn it into a
finished gaming machine: plugins, Windows-game compatibility, emulation, the game stores that
are not Steam, and game streaming. No terminal, no commands to copy, nothing to install by
hand.

> **Version 0.2.0.** It is careful and it undoes itself, and it leaves your games and saves
> alone.

## The problem this solves

A fresh SteamOS install is deliberately bare: no plugin system for the Steam interface, no
community build of Proton, no emulation, no way to play the games you already own on Epic or
GOG, no streaming, no Xbox Game Pass or GeForce NOW.

Every one of those is a solved problem, and every one is solved in a different forum thread,
with steps that contradict each other and advice that quietly breaks at the next system update.
Doing it by hand costs an afternoon — and a second afternoon the first time an update undoes
half of it. This tool does that work in one run, and can be run again after every update.

## What it installs

| What you get | What it does for you |
|---|---|
| **Decky Loader** | A plugin system that adds features to the Steam interface itself, reached from the Quick Access button while playing |
| **Seven Decky plugins** | Cover art for games that show as blank boxes (SteamGridDB), how well a game runs on handhelds (ProtonDB Badges), cloud saves for non-Steam games (Decky Cloud Save), interface themes (CSS Loader), reclaiming the space shader caches eat (Storage Cleaner), per-game battery use (Battery Tracker), and the RGB lights on handhelds that have them (HueSync) |
| **Proton-GE** | A community build of the layer that runs Windows games on Linux, which handles a good number of games the standard one struggles with. Set as the default, so every Windows game uses it without you choosing anything |
| **ProtonPlus** | A small app for updating that layer later, without this tool |
| **Heroic Games Launcher** | The games you already own on Epic, GOG and Amazon, in one app |
| **Lutris** | The games that come from no store at all — old Windows titles, standalone installers, anything with a community install script |
| **EmuDeck** | The standard emulation setup for handhelds. Downloaded and given a menu entry, with an `Emulation` folder created on your memory card when one is present; you run its own setup once and pick the consoles |
| **Sunshine** | Turns the handheld into a screen you can stream to another computer, with a Moonlight client at the other end |
| **SyncThingy** | Keeps folders — ROMs, saves — in sync with your desktop computer, over your own network |
| **Xbox Cloud Gaming** | A Steam library entry that opens Game Pass streaming full-screen with the controller working. No Linux app exists, so it goes through a browser configured for the job |
| **GeForce NOW** | NVIDIA's own SteamOS installer is run, which adds the service to your Steam library with the proper artwork |
| **Flatseal** | Lets you see and change what each installed app is allowed to reach |
| **Bazaar** | An app store you can browse with the gamepad instead of a mouse |

It also checks — and never changes — what SteamOS already handles: the controller service, the
power profiles, the TDP limits and the fan curves.

## What it deliberately does not do

**It never installs system packages.** This is the single most useful thing to know about
SteamOS. The system partition is read-only, and there are two of them: every update writes a
whole new one and reboots into it. Anything installed with `pacman` is simply gone afterwards,
along with any trace of why things stopped working. So this tool itself only writes to the
three places that survive an update — the Flatpak store, the Decky folder, and your home
directory. The Decky and Sunshine installers it runs also write under `/etc`: the Decky
service unit `plugin_loader.service` in `/etc/systemd/system`, and the Sunshine udev rule
`60-sunshine.rules` in `/etc/udev/rules.d`. Advice that starts with
`sudo steamos-readonly disable` will cost you an afternoon later.

It also does not:

- **replace the controller, TDP or fan handling.** SteamOS ships a service that owns the
  built-in controls, with per-model profiles. A second handheld daemon on top of it means two
  programs pulling at the same hardware, and the usual result is a handheld whose sticks do
  nothing. This tool checks that layer and reports what it finds.
- **install PowerTools or Fantastic** on hardware they were not written for. On a Steam Deck
  they are the right tool; elsewhere they fight the vendor's own driver.
- **change per-game settings.** It sets the global default compatibility tool and nothing else.
- **sign in anywhere for you**, collect anything, or send anything anywhere. It downloads from
  Flathub and from each project's own release pages, and that is all.
- **touch your ROMs, saves, installed games or accounts**, on installation or on removal.

## What you need

| | |
|---|---|
| **A handheld** | Any x86_64 AMD handheld running SteamOS 3.x, with Desktop Mode reachable |
| **Steam** | Signed in at least once, so there is a profile to configure |
| **A password** | Your SteamOS user password. SteamOS ships without one; if this handheld has never had one set, the tool offers to set it |
| **Space** | About 10 GB free in your home directory; around 1 GB is downloaded |
| **A memory card** | Optional. When one is present, ROM folders go there instead of the internal drive |

The memory card is found under `/run/media`: a card labelled `ROMS` if there is one, otherwise
the writable removable drive with the most free space. To name a different one, set
`HANDHELD_KIT_SD_MOUNT` to its mount point for the run, from a terminal:
`HANDHELD_KIT_SD_MOUNT=/run/media/<user>/<label> ./SteamOS-Handheld-Kit-*.AppImage`.

It is meant for AMD handhelds running SteamOS, the Steam Deck included — the components are the
same everywhere, and only the hardware checks differ, adapting to what the machine reports. It
refuses to run on anything that is not x86_64, because the compatibility layer, the plugin
loader and the emulation front-end are published for that architecture alone.

## How to run it

1. **Download** the `.AppImage` from the [latest release](../../releases/latest).
2. **Switch to Desktop Mode**, if you are not already there.
3. **Make it runnable**: right-click it, *Properties*, *Permissions*, tick *Is executable*.
4. **Double-click it**, and choose *Set it up*.
5. **Give it the password.** Installing the plugin system writes outside your home directory,
   which needs administrator rights, so a password box appears — this is expected. What you
   type is your own SteamOS password, handed to `sudo` and to nothing else: never written to a
   file, never in the log, never visible in the list of running programs. If this handheld has
   never had a password, the tool notices and offers to set one first, in the window it opened.
   You can decline either way, and everything that needs no administrator rights still
   installs; the plugin system is then reported as skipped, and nothing asks again.
6. **Watch it work.** A terminal window shows each step. Expect fifteen to forty minutes,
   mostly downloading.
7. **Read the summary**, one line per component: installed, updated, already present, skipped,
   failed, or *needs you*.

Running it again is safe, and is the intended way to use it: every step looks at the current
state before acting, so a second run fills in what is missing and leaves the rest alone. After
a major SteamOS update, run it again — the system partition is replaced and the plugin loader's
service goes with it.

It can also be driven from a terminal, which helps over SSH or when one part needs repeating:

```bash
./SteamOS-Handheld-Kit-*.AppImage --dry-run       # show what it would do
./SteamOS-Handheld-Kit-*.AppImage --verify        # check an existing setup
./SteamOS-Handheld-Kit-*.AppImage --only 30-decky # redo one part
./SteamOS-Handheld-Kit-*.AppImage --help          # everything else
```

## What is still yours to do

The summary lists each of these as **needs you**. None of them means something went wrong.

- **EmuDeck's own setup** asks which consoles you want and where the ROMs go — questions only
  you can answer. Start it from the application menu and point it at your memory card.
- **Signing in**: Epic and GOG in Heroic, whatever you use in Lutris, Xbox Game Pass, GeForce
  NOW. Each opens its own sign-in page the first time.
- **GeForce NOW's consent dialog.** NVIDIA's installer asks you to accept its terms before it
  does anything. If nobody was watching the screen, the summary says so — run it again from
  `~/Applications/GeForceNOW_Setup`.
- **Sunshine's username and password**, which you choose. Open the address the summary prints,
  on port 47990, set them, then pair your Moonlight client with the PIN it shows.
- **Pairing SyncThingy** with your computer, from its own interface.
- **One sign-out and back in**, if the summary says `/dev/uinput` is not writable yet. The
  permission that lets a streaming client move the mouse arrives with the next sign-in.

## How to undo it

Double-click the same file and choose **Remove it**. A password box appears first, because
removing the plugin system needs administrator rights. The terminal window that opens then
lists what it is about to remove and asks once, for you to type `REMOVE`, before it removes
anything: the applications, the plugin system, the compatibility layer builds, the menu entries
and its own working files. It ends with one line per component, removed or failed. Where no
terminal window can be opened, a dialog shows the same list and asks instead. From a terminal:

```bash
./SteamOS-Handheld-Kit-*.AppImage --teardown            # list, remove nothing
./SteamOS-Handheld-Kit-*.AppImage --teardown --confirm  # actually remove
```

The removal covers every component of those kinds, including copies that were already on the
handheld before the kit ran: any app on its Flatpak list, the whole `~/homebrew` folder with
its plugins and themes, and every GE-Proton build. It does not reset Steam's default
compatibility tool, and it leaves the Flatpak permission overrides and the user-scope Flathub
remote in place.

Your ROMs, saves, installed games and accounts are not touched. Two things it cannot remove for
you: entries already in your Steam library — remove those from Steam itself, with Steam open —
and the backups of Steam's configuration files, left next to the originals on purpose.

## When something does not work

**Nothing happens when I double-click it.** The file is probably not marked executable yet: see
step 3. If it is, run it from a terminal in that folder — the error it prints is the answer. A
message about FUSE means the system cannot mount the file; run it with
`--appimage-extract-and-run` instead.

**The plugin icon never appears in Game Mode.** The service runs, the plugins are installed,
the log is clean, and the icon is simply not there. This is a known failure: Decky's interface
hooks into Steam's own, and Steam occasionally renames the internals it hooks into. The fix
ships in Decky's pre-release builds:

```bash
HANDHELD_KIT_DECKY_CHANNEL=prerelease ./SteamOS-Handheld-Kit-*.AppImage --only 30-decky
```

**I cannot find the plugin menu at all.** It lives in the Quick Access menu, which a Steam Deck
opens with the `...` button. Handhelds without that button map it to their own: on an ASUS ROG
Ally it is the Armoury Crate button.

**My controller does nothing on the desktop.** Outside games Steam applies a separate
configuration, which for a non-Valve controller has to be switched on once, under *Steam →
Settings → Controller → show advanced settings*.

**It stopped halfway through.** Almost always the handheld suspended itself during a long
download. Run it again: it picks up where it stopped.

**The summary says an install fell back to "user scope".** That is fine. Installing an app for
the whole system needs a permission granted only to the session in front of the screen; the
fallback installs it for your user instead, in a place system updates also leave alone.

**Sunshine does not answer on port 47990.** Sign out and back in, then check again — the
permission it needs is granted at sign-in.

**Anything else.** Every run writes `~/steamos-handheld-kit.log`, with each command and its
output, and `~/steamos-handheld-kit-results.tsv`, one line per component. A removal writes its
own log, `~/steamos-handheld-kit-teardown.log`. Those are what to look at, and what to attach
if you open an issue.

## For contributors

- [docs/internals.md](docs/internals.md) — how it works inside, and the hard-won details that
  look arbitrary until you know what they avoid.
- [docs/design-decisions.md](docs/design-decisions.md) — why these components and not others,
  including what was considered and rejected.
- [CHANGELOG.md](CHANGELOG.md) — what changed in each release.

Building it needs an x86_64 Linux with `bash`, `python3`, `curl`, `coreutils` and `findutils`:

```bash
./build.sh   # checks the sources, then writes dist/SteamOS-Handheld-Kit-<version>-x86_64.AppImage
```

## Licence

[MIT](LICENSE). This tool installs software written by other people, each under its own licence
and downloaded from its own project. It bundles none of it.
