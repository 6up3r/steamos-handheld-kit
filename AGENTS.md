# Project instructions for coding agents

A bash and Python post-install kit for SteamOS handhelds, packaged as an AppImage. The setup
logic is in `src/`, the graphical launcher in `appimage/`.

## Build & run

- `./build.sh` writes `dist/SteamOS-Handheld-Kit-<version>-x86_64.AppImage`. It needs an x86_64
  Linux with `bash`, `python3`, `curl`, `coreutils` and `findutils`. It first runs `bash -n` on
  every script and compiles the Python; it runs `shellcheck` and `desktop-file-validate` when
  they are installed, and skips them otherwise.
- `src/setup.sh --dry-run`, `--verify` and `--only <module>` drive the setup from a checkout;
  `src/teardown.sh` lists what it would remove and `--confirm` removes it.
- Never run the setup or the teardown on a development machine: they install and remove
  software on the SteamOS host.

## Conventions

- The version lives in `src/VERSION` and must match the `v*` tag; the release workflow refuses
  a mismatch. The README banner and the CHANGELOG carry the number by hand.
- Modules in `src/modules` run in filename order, each in its own process. Each sources
  `src/lib/common.sh` and records one outcome per component with `record()`, its dry-run
  branch included (`PLANNED`). A module that only observes sets `OBSERVATION_ONLY=1` so its
  failures stay failures in a dry run.
- A privileged step checks `privileges_allowed()` first and records `SKIPPED` when it fails:
  after a declined password (`HANDHELD_KIT_NO_PRIVILEGES=1`) nothing may prompt again.
- The kit writes only to Flatpak, `~/homebrew` and the home directory, plus what the Decky and
  Sunshine installers put under `/etc`. It never installs system packages.
- CHANGELOG section headings (`## [x.y.z]`) are matched literally by the release step, which
  uses the section as the release notes: keep that heading format.

## Gotchas

Detail for each is in [docs/internals.md](docs/internals.md).

- Steam writes `shortcuts.vdf` and `config.vdf` back from memory on exit, so edits made while
  it runs are lost without an error; only `88-steam-config.sh` writes them.
- Decky's plugin icon can vanish after a Steam update with the service active and the logs
  clean; the fix needs both the pre-release binary and the channel setting.
- `flatpak install --system` needs polkit, which a remote shell does not get; the helper falls
  back to `--user`.
- PEP 668 blocks `pip install --user`; Python packages go in the virtual environment built by
  `ensure_python_vdf()`.

## How to work here

Before claiming a change done, run `bash -n` on every changed script and `python3 -m py_compile`
(or `ast.parse`) on every changed Python file, and on Linux run `./build.sh`.
