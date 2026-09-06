# Speek: build plan

Speek is a free, open-source macOS dictation app whose UI mirrors Superwhisper 2.18
(see `../reference/screenshots`), rebuilt on the Speek / VoiceInk codebase with a
macOS 26 Liquid Glass design. Local models only. No cloud speech or cloud LLM providers.

## Scope decisions

- Name: Speek. Bundle id `com.aveekpatra.speek`. URL scheme `speek://`.
- Platform: macOS 26.0+ only (Liquid Glass APIs, Apple Speech without availability checks).
- Voice models (local only): Parakeet V2/V3 (FluidAudio), Cohere Transcribe (FluidAudio
  CoreML q8), Whisper family (whisper.cpp), Apple Speech.
  Superwhisper's S1 models are proprietary and cannot be shipped; a matching "text
  reformat" slot is filled by local LLMs (Ollama) and the Claude / Codex CLI.
- Agent plugins: Claude Code and Codex, modeled on Superwhisper's hook integration
  (Stop / Notification / PermissionRequest / PreToolUse(AskUserQuestion) hooks -> a hook
  binary -> `speek://agent-update?...` -> Speek shows an overlay, user dictates, text is
  pasted back into the agent's terminal).
- Everything cloud-related in the inherited codebase is removed from the UI and registry
  first, then deleted from source in a cleanup pass.

## UI map (Superwhisper parity)

Sidebar: Home, Modes, Vocabulary, Configuration, Sound, Models library, History, and a
footer "Speek" button (About: version, GitHub, updates).
Toolbar (trailing): current microphone name + device menu.

| Page | Content |
|---|---|
| Home | Range picker (All time / Today / Week / Month), stats strip (WPM, words, apps used, time saved), Get started list, What's new |
| Modes | List (+ Create mode), detail: preset, language, voice model, activate for apps, keyboard shortcut, advanced (playback, autocapitalize, auto paste), delete |
| Vocabulary | Add word / Replace with, list, edit replacement panel |
| Configuration | Appearance (theme, recording window Classic/Mini/None), Keyboard Shortcuts (toggle, cancel, change mode, push to talk, mouse), Application (updates, launch on login, error logging, keep recordings), Advanced settings page (dock, menubar click, always close, model active duration, app folder, text input, agent plugins, experimental models) |
| Sound | Recording (auto gain, silence removal, dynamic normalization, playback when recording), Sound effects (Simple/Classic/Off, volume) |
| Models library | Search, provider filter, table: name, type, speed/accuracy, size + download/installed |
| History | Search, grouped by date, detail with audio player |

Recording window styles: Classic (wide waveform panel with mode name, Stop and Cancel
hints), Mini (pill), None.

Menu bar: Toggle Recording, Transcribe File, History, Settings, microphone submenu, mode
submenu, version, Check for Updates, Quit.

## Phases

1. Rebrand + macOS 26 target + new shell (NavigationSplitView, sidebar, toolbar). DONE.
2. Pages: Configuration, Sound, Models library, Vocabulary, Modes, History, About. DONE.
3. Recording windows (Classic, Mini, None) + menu bar menu + sound effects + mode switcher. DONE.
4. Cohere Transcribe via FluidAudio main; model table wiring. DONE.
5. Agent plugins (Claude Code, Codex): hook script, installer, overlay, reply path. DONE.
6. Cleanup: cloud speech providers, license, coach, dashboard, stickers, old recorder and settings UI deleted (DONE); onboarding rewrite (DONE); README/PRD rewrite (DONE). Still inherited: cloud LLM providers inside AIService (unused by the UI), legacy recorder widget files, iOS targets (not built).
