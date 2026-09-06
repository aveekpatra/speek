# Speek: Product Requirements Document

## 1. Product vision

Speek is a free, open-source macOS dictation app that matches the Superwhisper workflow
and look (see `reference/screenshots/`) while running every model locally. Press a
shortcut, speak, and clean text lands in the focused app.

## 2. Target user

Mac users who want Superwhisper-class dictation without a subscription or cloud
processing, including developers who drive coding agents (Claude Code, Codex) by voice.

## 3. Scope

- macOS 26.0 or later only. Liquid Glass design, Apple Human Interface Guidelines.
- Local models only. No cloud speech or cloud LLM providers in the UI or registry.
- No licensing, trials, or accounts.

## 4. Core flows

### 4.1 Dictate
1. Press the Toggle Recording shortcut (default: right Command, modifier only) or the Push to Talk key.
2. The recording window appears centred at the bottom of the screen the pointer is on (Classic panel, Mini pill, or None). With Mini's "Always show" on, a thin strip stays on the chosen edge and expands on hover into change-mode, record, and open-app controls. The recorder and the agent reply panel share one anchor: the bottom edge (or the top edge under the menu bar, or the side edge) stays locked while the panel grows away from it, and side placements stay vertically centred.
3. Press the shortcut again (or Escape to cancel). Speek transcribes with the active mode's voice model, applies vocabulary replacements and formatting, optionally rewrites with a local text model, then pastes into the focused app. Holding Shift while stopping presses Return after pasting.

### 4.2 Modes
A mode combines a preset (Voice to text, Message, Email, Note, Custom prompt), a language, a voice model, a text model (S1-mini with tone and structure controls, or an Ollama model), app and website triggers, a shortcut, and advanced options (autocapitalize, auto paste, auto send). Modes switch automatically by front app or site, by shortcut, or through the mode switcher (default ⌥⇧K).

### 4.3 Models library
Table of voice models (Cohere Transcribe, Canary 1B v2, Parakeet V2/V3/110M/Japanese, Whisper Large v3 Turbo, Apple Speech, imported GGML files) and text models (S1-mini, Ollama models) with type, speed and accuracy meters, size, download progress and the active model. Provider filter, search, import.

### 4.4 Agent plugins
Connecting Claude Code or Codex installs Speek as a real plugin of that agent (Claude: `speek@speek` under Plugins; Codex: `speek@speek` under /plugins, with the hook trust Codex requires recorded automatically). When an agent finishes, needs permission, or asks a question, the reply panel takes the recording pill's place; the hook waits and returns the spoken or typed reply as hook output. A user prompt submitted in the terminal dismisses the entry.

### 4.5 First run
Welcome, permissions (Microphone, Accessibility), voice model download, shortcut.

## 5. UI map

| Sidebar item | Content |
|---|---|
| Home | Range picker, stats (WPM, words, apps used, time saved), Get started, What's new |
| Modes | Mode list, Create mode, mode detail |
| Vocabulary | Add word / Replace with, list, replacement editor, import/export |
| Agent Panel | Connect Claude Code and Codex; panel position (Bottom, Top, Left, Right, shared with the recording pill), sound, auto-send, hide duration, preview; per-project mute |
| Configuration | Appearance (theme, recording window, always show), Keyboard Shortcuts, Application, Advanced settings (Dock, voice model active duration, app folder, clipboard and paste) |
| Sound | Recording toggles, playback behavior, sound effects style and volume |
| Models library | Model table |
| History | Search, date groups, detail with audio player and metadata, clear all |
| Speek (footer) | Version, updates, credits, links |

Menu bar: Toggle Recording, Transcribe File..., History..., Settings..., microphone and mode submenus, version, Check for Updates..., Quit.

## 6. Technical overview

- SwiftUI app (`SpeekApp` in `Speek/SpeekApp.swift`), `NavigationSplitView` shell in `Speek/UI/Shell/`, pages in `Speek/UI/Pages/`, design tokens and components in `Speek/UI/Design/`.
- Settings store: `SpeekSettings` (UserDefaults-backed, `speek.*` keys, mirrors legacy keys the engine reads).
- Transcription: `TranscriptionServiceRegistry` dispatches to `WhisperTranscriptionService` (whisper.cpp), `FluidAudioTranscriptionService` (Parakeet), `CohereTranscriptionService` (FluidAudio `CoherePipeline`), `CanaryTranscriptionService` (FluidAudio `CanaryManager`), `NativeAppleTranscriptionService`.
- Text normalization: `S1MiniService` runs the S1-mini GGUF through `LlamaRunner` (llama.cpp XCFramework); `AIProvider.s1Mini`.
- Model downloads: `WhisperModelManager`, `FluidAudioModelManager`, `CohereModelManager` (ModelHub download of `FluidInference/cohere-transcribe-03-2026-coreml/q8`).
- Recording window: `MiniWindowManager` hosts `SpeekRecorderView` (Classic / Mini) in a non-activating floating panel; `RecorderUIManager` drives it.
- Agent plugins: `AgentHookInstaller`, bundled `speek-agent-hook.sh`, `AgentUpdateCenter` (URL scheme `speek://agent-update`, overlay, reply routing in `TranscriptionDelivery`).
- Persistence: SwiftData stores (transcripts, vocabulary, session metrics) under Application Support.
- Permissions: Microphone, Accessibility; Apple Events for browser URL detection (Modes). App Sandbox disabled.
- Updates: Sparkle, feed at `appcast.xml` in this repository.

## 7. Non-goals

- Cloud transcription or cloud LLM providers.
- iOS, Windows, Linux.
- Paid features, licensing, telemetry.
- Superwhisper's proprietary S1 models (not redistributable).

## 8. Status

All phases of `PLAN.md` are implemented. Remaining: prune the cloud LLM providers left inside `AIService`, remove the iOS targets from the project, notarized release builds, Sparkle signing key and appcast publishing.
