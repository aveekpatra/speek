# MediaRemoteAdapter (vendored)

Prebuilt from https://github.com/ungive/mediaremote-adapter, tag v0.7.7 (BSD-3-Clause, see LICENSE).

Speek uses it to read what is playing and to pause/resume it while recording
("Playback when recording: Pause"). macOS 15.4 and later only let Apple-signed
binaries talk to MediaRemote, so the framework is never linked: Speek runs
`/usr/bin/perl mediaremote-adapter.pl <framework> get|send ...` and reads JSON.

- `MediaRemoteAdapter.framework` is embedded (Copy Files, not linked).
- `mediaremote-adapter.pl` is a bundle resource.

To rebuild from source: `scripts/build-mediaremote-adapter.sh`.
