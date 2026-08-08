# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the versions
follow [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-08

First public release. The setup logic behind it has been exercised on real hardware; the
packaging around it is new, and the honest summary of what that means is at the bottom of this
section.

### Added

- **Post-installation setup for AMD handhelds running SteamOS**, as eleven modules run in
  dependency order, each of which checks the current state before acting so the whole run can
  be repeated safely.
  - Hardware enablement is verified, never replaced: the controller service and its device
    profile, the virtual gamepad, the vendor kernel modules, the power profiles, the TDP
    controls and the fan curve interface.
  - Flatpak groundwork: the Flathub remote, an index refresh, an update pass, Flatseal and
    Bazaar.
  - Decky Loader and seven plugins, resolved from the store index and verified against the
    checksum that doubles as the archive's address.
  - Proton-GE and ProtonPlus, with the release archive checked against the checksums the
    release publishes, and Proton-GE set as the global default compatibility tool.
  - Heroic Games Launcher for the storefronts and Lutris for the games that come from no store,
    each with the sandbox permissions it needs to see Steam's compatibility tools and the
    memory card.
  - EmuDeck, downloaded and given a menu entry, with the ROM folder created on the memory card.
  - Sunshine, with the udev rule and user service its own package installs, and a check that
    `/dev/uinput` is really writable rather than that a group exists.
  - SyncThingy.
  - Xbox Cloud Gaming through a browser in kiosk mode, as a menu entry and as a Steam library
    entry; GeForce NOW through NVIDIA's own SteamOS installer.
  - A final verification that interrogates the running system, and a per-component summary
    naming what is installed, what was already there, what was skipped, what failed and what
    still needs the user.
- **A teardown** that removes exactly what the setup installs, listing it first and asking
  before it acts, and that leaves ROMs, saves, installed games and credentials alone.
- **An AppImage** that runs the whole thing from a double click: a menu of actions, one
  graphical password prompt, and the run shown in a terminal window opened on purpose so a long
  download does not look like a hang. Where no terminal emulator exists it falls back to a
  progress dialog fed from the log.
- **A first boot with no password leads somewhere.** SteamOS ships the user account without
  one, and `sudo` rejects everything typed at it until one exists. The state is read before
  anything is asked, and where the launcher has a terminal it offers to set the password there
  with `passwd`, then grants the administrator rights from that same window. Declining installs
  everything that needs none.
- **A build script** that checks every source file, draws the icon, verifies the packaging tool
  against a pinned checksum and produces the AppImage, and a GitHub Actions workflow that runs
  it and attaches the result to a tagged release.

### Tested

All of the following was exercised on one machine: an ASUS ROG Xbox Ally on SteamOS 3.8, build
20260807.2, x86_64.

- The setup end to end, and its verification pass against the running system: 36 checks,
  nothing missing.
- A full dry run, reporting every component with an outcome and changing nothing.
- The released AppImage, downloaded from the release page and checked against its published
  checksum: it mounts through FUSE and answers `--version`, `--help`, `--dry-run`, `--verify`,
  `--only <module>` and `--teardown`.
- **The whole double-click path**, driven from outside in Desktop Mode: the menu returns the
  action chosen, the terminal opens and the run happens inside it, closing that window records
  the outcome, and the outcome dialog appears and dismisses.
- **The first-boot password branch end to end**, against a stand-in for `passwd` that reports
  no password until one is set: the question, `passwd` running in the terminal and accepting
  what is typed there, sudo asked in the same window, the dialog taking over when that is
  declined, and the continue-without-rights fallback.
- The password probe's five outcomes, and the branch it selects from them.
- The launcher's worker, headless and inside a terminal window: it records that it started,
  records its outcome, and refuses to start twice over the same run.
- The generalised detection against the real machine: the memory card found by its mount point,
  the controller profile found through the firmware board name, the vendor kernel modules, and
  the TDP interface.

### Not tested

- **A genuinely fresh account with no password.** Producing one would mean removing the
  password from the only machine available. The branch was exercised against a stand-in for
  `passwd`; the real one, on a real account in that state, has not been.
- **The administrator password being accepted**, which only the account's owner can type.
  Everything on either side of that moment was exercised.
- Any second machine, of any model. The Steam Deck in particular has never run this.
- Any operating system other than SteamOS 3.8.
- Any desktop other than the one SteamOS ships, so the fallbacks for a missing terminal
  emulator and for a kdialog-only desktop are reasoned, not observed.
- Recovery from a run interrupted at an arbitrary point. Re-running is designed to be safe and
  behaves so in the cases that were tried; the space of interruption points is larger than what
  was covered.
