# AGENTS.md

Notes for anyone, human or AI agent, changing this code. `README.md` covers using it and what the installer sets
up; this file covers how the scripts fit together and what to keep in step when changing them.

## What this is

Offline text-to-speech for Omarchy (Arch Linux with Hyprland), written in Bash. A `speak` command queues text, a
systemd user service (`speakd`) plays the queue through Piper and PipeWire, and optional hooks speak the current
selection, low-battery warnings and Claude Code answers. It runs on Linux only (x86_64 and aarch64) and needs `jq`,
`curl` and PipeWire's `pw-play`.

## Commands

```bash
./install.sh                     # per-user install into ~/.local; safe to re-run
./install.sh --no-keybindings --no-battery-hook --no-claude-hook   # skip the optional pieces
./uninstall.sh [--purge]         # --purge also removes voices and the config
bin/speak "test"                 # works from the checkout: it finds ../lib/speak-lib.sh
bash -n bin/* lib/*.sh install.sh uninstall.sh   # syntax check
```

There are no tests and no CI workflow. `install.sh` changes the user's Hyprland bindings and Claude Code settings,
so try it on a test account or with the `--no-*` options.

## Layout

- `lib/speak-lib.sh`: shared helpers, sourced and never run.
  - `speak_load_config` reads `~/.config/speak/config` and sets defaults (voice, rates, `SPEAK_MAX_CHARS`) and the
    runtime paths under `$XDG_RUNTIME_DIR/speakd`.
  - `speak_piper_bin`, `speak_model`, `speak_clean` (flattens Markdown for reading aloud) and `speak_play`.
- `bin/speak`: the CLI (`now`, `stop`, `voices`, `install-voice`, `speakers` and options `-v`, `-s`, `-r`,
  `--raw`).
  - `enqueue` writes one file per utterance into the spool.
  - `now` stops playback and clears the queue first.
  - When `speakd` isn't running it plays synchronously instead.
- `bin/speakd`: the daemon loop; plays spool files oldest first.
- `bin/speak-selection`, `bin/claude-speak-response`, `hooks/battery-low/speak-battery-low`: thin callers of
  `speak`.
- `config/config.example`: the config template (`@DEFAULT_VOICE@` is filled in by the installer).
- `systemd/speakd.service.in`: the user unit (`@BINDIR@` is filled in).
- `install.sh`, `uninstall.sh`, `PKGBUILD`: per-user install, removal, and the Arch package.

## Rules that keep it working

- **Spool file format.** The first line is `voice<TAB>speaker<TAB>rate<TAB>noise<TAB>noise_w`; the rest is the text.
  Files are written to `tmp/` and then `mv`ed into `spool/`, so the daemon never reads half a file. Names are
  zero-padded nanosecond timestamps, so `ls` order is queue order. Change `enqueue` and `speakd` together.
- **Playback has its own process group.** `speak_play` starts `piper | pw-play` with `setsid` and records the PID;
  `speak stop` kills the whole group. Keep new pipeline stages inside that `setsid`.
- **Finding the library.** Scripts look for it at `$SPEAK_LIB`, `../lib/speak-lib.sh` next to the script,
  `/usr/share/speak/lib.sh` (package) and `~/.local/share/speak/lib.sh` (installer). Keep all four paths if you
  move files.
- **Three install routes stay in step.** A new script or data file must be added to `install.sh`, `uninstall.sh`
  and `PKGBUILD`.
- **Pinned downloads.** `install.sh` pins the Piper release (`PIPER_VERSION`) and its SHA-256 per architecture;
  update both together. `PKGBUILD` pins the `v1.0.0` source tarball's checksum; a new release needs a new
  `pkgver` and `sha256sums`.
- **Re-runs must stay safe.** The installer leaves an existing config, voice, keybinding or hook alone.
