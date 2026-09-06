# omarchy-speak

Local neural text-to-speech for [Omarchy](https://omarchy.org/). The counterpart to
dictation: instead of talking to your machine, your machine talks to you.

Runs entirely offline on [Piper](https://github.com/rhasspy/piper) — no API key, no
network, no per-character billing. Roughly 0.2s to synthesize a sentence on an ARM VM.

```bash
speak "build finished"           # queue it
make 2>&1 | speak                # read from stdin
speak now "look at this"         # jump the queue
speak stop                       # shut up
```

## Install

```bash
git clone https://github.com/harlock123/omarchy-speak
cd omarchy-speak && ./install.sh
```

No root required — it installs into `~/.local`, downloads the Piper binary for your
architecture (checksum-verified against the `piper-tts-bin` PKGBUILD), fetches a voice,
and enables a systemd **user** service. Re-running it is safe: an existing config,
voice, or keybinding is left alone.

Options: `--voice NAME`, `--no-keybindings`, `--no-battery-hook`, `--no-claude-hook`,
and `--system` (per-user setup only, when the binaries came from a package).

Remove with `./uninstall.sh` (add `--purge` to delete voices too).

### As an Arch package

`PKGBUILD` builds a system-wide package that depends on the `piper-tts` AUR package.
After installing it, each user still runs the per-user setup once:

```bash
/usr/share/speak/setup.sh --system
```

This mirrors how Omarchy ships dictation: an AUR package plus a per-user setup step.

## What it sets up

| Piece | Purpose |
|---|---|
| `speak` | the CLI |
| `speakd` | systemd user service; serializes utterances so nothing talks over anything else |
| `speak-selection` | speaks the current selection, bound to `SUPER+ALT+V` |
| `claude-speak-response` | Claude Code `Stop` hook, so Claude reads its answers aloud |
| battery-low hook | Omarchy speaks the low-battery warning |

`SUPER+ALT+X` stops playback.

## Voices

176 voices across 57 languages. There are no emotional style presets; variety comes from
the voice model, the speaker index inside multi-speaker models, and prosody.

```bash
speak voices                                  # what's installed
speak install-voice en_GB-vctk-medium         # 109 voices in one 73MB file
speak speakers en_GB-vctk-medium              # → select with -s 0 .. -s 108
speak -v en_GB-vctk-medium -s 42 -r 1.2 "slower, different voice"
```

Browse the catalog at [huggingface.co/rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices).

Defaults live in `~/.config/speak/config` (`SPEAK_VOICE`, `SPEAK_LENGTH_SCALE`,
`SPEAK_NOISE_SCALE`, `SPEAK_NOISE_W`, `SPEAK_MAX_CHARS`); every one can be overridden per
invocation by an environment variable. Restart with `systemctl --user restart speakd`.

## How it works

`speak` writes each utterance to a spool directory as a timestamped file; `speakd` plays
them oldest-first. Playback runs in its own process group, so `speak stop` kills the whole
`piper | pw-play` pipeline instead of orphaning half of it. If the daemon isn't running,
`speak` falls back to synchronous playback rather than silently doing nothing. Markdown is
flattened before synthesis — code fences become "code block", URLs become "link" — because
reading raw markdown aloud is unbearable.

## Requirements

Omarchy (or any Wayland Arch system) with PipeWire, plus `jq`, `curl`, and `wl-clipboard`
for the selection key. x86_64 and aarch64.

## License

MIT
