<div align="center">
  <h1>Speek</h1>
  <p>Free, open-source dictation for macOS. Every model runs on your Mac.</p>
  <p>
    <img src="https://img.shields.io/badge/platform-macOS%2026%2B-brightgreen" alt="macOS 26+">
    <img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="GPL-3.0">
  </p>
</div>

Press a shortcut, speak, and the text lands wherever your cursor is. Speek mirrors the
workflow of Superwhisper with a macOS 26 Liquid Glass interface, and it only ever uses
local models: nothing you say leaves your Mac.

## Features

- **Local voice models**: Cohere Transcribe (open 2B model, 14 languages), NVIDIA Canary 1B v2 (25 European languages), NVIDIA Parakeet V2/V3/110M/Japanese, Whisper Large v3 Turbo (whisper.cpp), and Apple Speech.
- **Modes**: presets (Voice to text, Message, Email, Note, Custom) with per-mode language, voice model, text model, app and website triggers, and shortcuts.
- **Local text models**: S1-mini by Superwhisper (open-weights transcript normalizer, runs through llama.cpp, with tone and structure controls) or any Ollama model.
- **Agent plugins**: Claude Code and Codex notify Speek when they finish, need permission, or ask a question; answer by voice and the reply is typed into their terminal.
- **Recording window styles**: Classic (compact waveform panel), Mini (pill), or None. Mini has an "Always show" option: a thin strip stays on the top, left, or right screen edge and expands on hover into change-mode, record, and open-app controls.
- **Vocabulary and replacements**, searchable history with audio playback, and a menu bar app with Transcribe File.
- **Sound effects** (Simple / Classic / Off), silence removal, dynamic normalization, playback pause while recording.

## Install

Download the latest `.dmg` from [Releases](https://github.com/aveekpatra/speek/releases),
open it, and drag Speek to Applications. On first launch Speek asks for Microphone and
Accessibility access and lets you download a voice model.

## Build from source

Requires macOS 26, Xcode 26, and CMake (`brew install cmake`).

```bash
git clone https://github.com/aveekpatra/speek.git
cd speek
make local
```

`make local` builds `whisper.cpp` as an XCFramework the first time (a few minutes); `llama.cpp` is built the same way (`~/Speek-Dependencies/llama.cpp`, `./build-xcframework.sh macos`), then
produces an ad-hoc signed `Speek.app`. During development use `scripts/dev-build.sh` for
incremental builds and `scripts/dev-show.sh <page>` to launch on a given page.

## Agent plugins

Configuration > Advanced settings > Agent Plugins installs a small hook script into
`~/Library/Application Support/Speek/hooks/` and wires it into:

- **Claude Code**: `~/.claude/settings.json` hooks for Stop, Notification, PermissionRequest, PreToolUse (AskUserQuestion), and UserPromptSubmit.
- **Codex**: `~/.codex/hooks.json` (Codex's native hooks) for Stop, PermissionRequest, and UserPromptSubmit. Your `notify` setting is left alone.

When the agent finishes, asks a question, or needs permission, a reply panel appears at
the recording pill's spot: a pill per waiting session (agent icon, project, git branch),
the selected agent's message rendered as markdown, and a reply card. Press your recording
shortcut and speak (the transcript lands in the box), type, paste or drop screenshots,
then Return sends. Nothing is typed into the terminal: the hook itself waits for your
answer and returns it to the agent as hook output (a Stop hook "block" with your reply as
the reason, an allow/deny decision for permissions, the chosen option for questions), so
the agent continues in the background while you stay where you are. Images are saved
under Application Support and sent as file paths the agent opens with its Read tool.
Esc dismisses the selected session and lets that agent stop normally; several agents can
wait at once and you answer them one by one. Answering in the terminal closes that
session's panel automatically.

Both agents also get a `/speek` skill (`on`, `off`, `status`) that mutes the hook for
the current project directory. Uninstall from the same screen removes everything.

## Project layout

- `Speek/UI/`: the Speek UI (design system, sidebar, pages, recorder windows, agent plugins, onboarding).
- `Speek/Transcription/`: engines (Whisper, FluidAudio Parakeet, Cohere, Apple Speech) and the recording pipeline.
- `Speek/Modes/`: mode configuration and app/site triggers.
- `reference/screenshots/`: Superwhisper screenshots used as the UI reference.

Speek grew out of
[Whisper Pro](https://github.com/ZdenekCulik/whisper-pro), itself a fork of
[VoiceInk](https://github.com/Beingpax/VoiceInk). Cloud providers, licensing, the English
coach, and the iOS keyboard from that lineage are not part of Speek.

## Acknowledgments

[whisper.cpp](https://github.com/ggerganov/whisper.cpp), [FluidAudio](https://github.com/FluidInference/FluidAudio),
[Cohere Transcribe](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026),
[Sparkle](https://github.com/sparkle-project/Sparkle), [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin-Modern),
[LLMkit](https://github.com/Beingpax/LLMkit), [SelectedTextKit](https://github.com/Beingpax/SelectedTextKit),
[MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter), [Zip](https://github.com/marmelroy/Zip).

## License

GNU General Public License v3.0, see [LICENSE](LICENSE).
