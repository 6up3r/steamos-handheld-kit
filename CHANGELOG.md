# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the versions
follow [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-10-09

Fixes for defects found by reading 0.1.0's code: most of them in the dry run, the removal and
the way the launcher handles the password. None of these changes has run on a handheld yet,
and the honest summary of how they were checked is at the bottom of this section.

### Fixed

- **A dry run changes nothing.** It created `~/homebrew/plugins` and
  `~/.local/share/applications` before checking whether it was a dry run, so its closing line,
  "nothing was changed", was not quite true. Both are now left alone.
- **A dry run lists every component.** The Decky plugins and the pre-release channel,
  Proton-GE, EmuDeck, Sunshine's udev rule and service, the Xbox Cloud Gaming entry, GeForce
  NOW and the two writes to Steam's configuration were missing from its summary, because their
  module ended before recording an outcome. Each now appears as planned.
- **A dry run reports what it found as found.** The hardware check's failures, and a module
  ending with an error, were shown as planned in a dry run. They are real observations, and
  are shown as failed.
- **Other vendors' handhelds no longer fail the setup over the fan.** The fan check knows the
  ASUS and Steam Deck interfaces only, and on any other vendor it reported a failure that made
  the whole run end in error. It now reports the check as skipped, naming the vendor.
- **No memory card is no longer a failed verification.** The card is optional, yet its absence
  counted as a missing entry, so every verification without one ended in failure. It is now a
  note that is not counted; with a card present the number of checks is unchanged.
- **The default compatibility tool is checked where Steam reads it.** The verification passed
  whenever the Proton-GE name appeared anywhere in `config.vdf`, a per-game choice included. It
  now reads the global default itself, `CompatToolMapping` `"0"`.
- **`--only` asks for the password whenever the run needs it.** A fragment found inside the
  name of a module that needs no privileges skipped the request even when it also selected
  others: `--only 0` ran the Decky installer without a password. The decision is now made on
  the exact list of modules the run will execute, `--skip` included.
- **Declining the password in the launcher is final.** The run then asked again in the
  terminal, and the Decky steps called `sudo` regardless. The steps that need administrator
  rights are now reported as skipped without asking, and everything else still installs.
- **The removal asks once, after showing what it removes.** The launcher asked a question
  before anything was listed, and the terminal then asked for a typed `REMOVE`. The terminal's
  question, after the list, is now the only one; where no terminal window can be opened, the
  launcher's dialog carries the same list.
- **The removal reports its real outcome.** It always ended with "Removal complete." and status
  0. It now prints one line per component and ends with status 1 when anything failed to come
  off, so the launcher's closing dialog says so too.
- **`--only`, `--skip` and `--log` without a value** stopped silently with status 1. They now
  say which option needs a value and stop with status 2.
- **No temporary files left behind** by `--help`, `--version`, a mistyped option, a failed
  preliminary check, or a removal that only lists.
- **The launcher no longer stops when `USER` is unset**, as it can be in a session started by a
  service manager.
- **Downloaded installers no longer go to fixed names in `/tmp`.** The Decky installer, the
  pre-release loader and the script that installs it with `sudo`, the plugin archives and the
  GeForce NOW archive now go to files created for the run alone, removed when the module ends.
  None of them gained a checksum: their projects publish none to check against.
- **GeForce NOW is not reinstalled on every run.** NVIDIA's installer, consent dialog included,
  ran again even with the entry already in the Steam library. That is now reported as already
  present, and the installer is left alone.
- **A plugin upgrade is reported as updated**, with the old and new version, instead of as
  installed.

### Changed

- `steam_config.py` gains `--print-proton`, which prints the global default compatibility tool
  and changes nothing; `--userdata` is needed only with `--shortcut-name`.
- The release is published by a job of its own, which runs only on `v*` tags and alone holds
  write access to the repository. The build, which also runs on pull requests and branch
  pushes, can only read. The release notes stop before the link references at the bottom of
  this file, which used to end up in the notes of the oldest release.

### Tested

Nothing in 0.2.0 has run on a handheld, nor on SteamOS. The changes were checked statically on
a development machine: `bash -n` on every shell script, `shellcheck` with no finding beyond the
ones 0.1.0 already had, and `ast.parse` on both Python files. On top of that, the changed
modules and functions were run in isolation against 0.1.0 on the same inputs, each in a
scratch home directory, with `sudo`, `flatpak`, `systemctl`, `curl` and the other system tools
replaced by stand-ins: a dry run of every changed module, the hardware check on an unknown
vendor, the verification with and without a memory card and against a `config.vdf` whose
default is not Proton-GE, the privilege decision for a range of `--only` and `--skip` values,
the declined-password path through the Decky module and the removal, the removal's summary
and status, the option errors and temporary files, a plugin upgrade, and GeForce NOW already in
the library. The release-notes extraction was run on this file; the workflow itself has not
run.

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
- **A teardown** that removes every component of the kinds the setup installs, listing them
  first and asking before it acts. That includes copies already present before the kit ran:
  any app on its Flatpak list, the whole `~/homebrew` folder with its plugins and themes, and
  every GE-Proton build. It does not reset Steam's default compatibility tool, and it leaves
  the Flatpak permission overrides and the user-scope Flathub remote in place. ROMs, saves,
  installed games and credentials are left alone.
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
- A full dry run, which shows what each module would do. Some components report no outcome in
  the summary, because their module ends before recording one.
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

[Unreleased]: https://github.com/6up3r/steamos-handheld-kit/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/6up3r/steamos-handheld-kit/releases/tag/v0.2.0
[0.1.0]: https://github.com/6up3r/steamos-handheld-kit/releases/tag/v0.1.0
