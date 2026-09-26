# Speek: Current product requirements

Updated: 2026-09-26.

## Current direction

Speek is a cloud-connected macOS voice-to-action assistant. Users can dictate into the current app, rewrite selected text, ask questions with screen/file context, and request actions through connected tools. The application combines a persistent notch assistant with in-app Tasks, Memory, Models & Voice, Integrations, and Settings.

The current feature inventory and remaining limitations are in [docs/FEATURE_STATUS.md](docs/FEATURE_STATUS.md). That document distinguishes implemented source paths from live-tested capabilities. Neither this PRD nor a passing build establishes full VoiceOS parity or production readiness.

## Current workflows

- Dictation: hold the shortcut, or opt into double-tap hands-free capture; transcribe, apply corrections and the selected writing mode, then insert only into the captured valid destination. Preserve text when delivery is unsafe.
- Edit: explicitly enable selected-text editing, capture the selection, speak the edit, and replace only if the original selection still matches.
- Agent: capture fresh permitted context, select a connected tool, validate arguments, review consequential actions, execute and report the actual result. Continue dependent steps within execution limits.
- Integrations: configure MCP servers, supported native apps, trusted CLI manifests, scoped dictation hooks and local instruction skills. Unavailable services must not be represented as connected.
- Coding: configure Codex or Claude Code under Integrations > Local tools. Use a request review sheet; show progress and results on the Coding tasks subpage. Activity does not list coding jobs.
- Settings ownership: Each setting has one home. Models & Voice: accounts, default provider/model/reasoning for new chats, voice connection, dictation and speech models, voice, spoken replies and speaking speed. Settings: General (speak shortcut, double-tap hands-free, screen context, launch at login), Dictation (microphone, recognition language, vocabulary hints, writing mode and style, Edit Mode), Privacy (save history, recording recovery), Permissions (Microphone, Accessibility, Screen Recording). Memory: Facts, Episodic, Procedural, Vocabulary (names, terms, corrections, spoken shortcuts). Integrations: Plugins, Native apps (Calendar, Reminders, Mail, Notes, music, Messages, Files working folder), Local tools (Codex and Claude Code, CLI manifests, hooks), Skills. App-specific macOS access is requested from its integration card.
- Memory: maintain explicit facts, dated completed-request/result episodes, user-authored procedures and transcription corrections. Respect history opt-out and allow inspection, editing and removal.
- Activity: show background requests and integration jobs together. Schedules create reviewable due requests while Speek is running; they do not silently grant permission for external writes.
- Recovery: optional local audio backup, bounded by age/count/disk size, for retry and copying. Keep it off by default and disable new backups when history saving is off.

## Design and acceptance requirements

Preserve the established notch design. In-app screens use the current settings background, consistent type hierarchy, compact flat action buttons beside section headings, shared card surfaces, responsive grids and right-aligned controls. Reuse existing model controls and actual provider identities.

Each feature needs real persistence and error handling, cancellation where work is asynchronous, and a reachable empty/loading/error state. Do not show fake success, silently reset user selections, hide unsupported behavior behind placeholder buttons, or claim completion without a tool result. Missing credentials or account permissions must be explicit.

Verification includes source helper checks, a signed app build, and permission/account-dependent manual checks. Retain the stable Speek Dev Signing identity and canonical Applications install. Production release requires the outstanding tests and implementation gaps recorded in FEATURE_STATUS.md to be resolved or explicitly scoped out.

## Current boundaries

The active lifecycle uses cloud speech and request providers. Local model downloads and inference in the historical implementation are not the current product direction. Subscription request authentication and speech API credentials remain separate. Computer use, the full third-party OAuth catalog, rich integration widgets, cross-platform clients and enterprise services are not implemented merely because local abstractions exist.

---

# Historical appendix: retired local-dictation requirements

The remainder is preserved as historical reference. It describes the pre-pivot product, including retired local-only models, former navigation, old recorder placement, and legacy plugin behavior. It is not the current implementation contract and must not override the requirements above.

## 1. Product vision

Speek is a free, open-source macOS dictation app that runs every model locally. Press a
shortcut, speak, and clean text lands in the focused app.

## 2. Target user

Mac users who want high-quality dictation without a subscription or cloud
processing, including developers who drive coding agents (Claude Code, Codex) by voice.

## 3. Scope

- macOS 26.0 or later only. Liquid Glass design, Apple Human Interface Guidelines.
- Local models only. No cloud speech or cloud LLM providers in the UI or registry.
- No licensing, trials, or accounts.

## 4. Core flows

### 4.1 Dictate
1. Press the Toggle Recording shortcut (default: right Command, modifier only) or the Push to Talk key.
2. The recording window appears centred at the bottom of the screen the pointer is on (Classic panel, Mini pill, or None). With Mini's "Always show" on, a thin strip stays on the chosen edge and expands on hover into change-mode, record, and open-app controls. The pill's anchored edge stays locked while it grows; the agent reply panel has its own Bottom / Center / Top position, is always horizontally centred on the full screen, and grows away from its anchor.
3. Press the shortcut again (or Escape to cancel). Speek transcribes with the active mode's voice model, applies vocabulary replacements and formatting, optionally rewrites with a local text model, then pastes into the focused app. The paste is always attempted. When the focused control cannot be confirmed as a text field beforehand (Gecko browsers and Electron apps often hide it), Speek watches the app during the paste: if the focused control reports a text change, or its value now holds the text, the recorder closes as usual (and the previous clipboard is put back); otherwise the recorder stays up with a Copy button. Holding Shift while stopping presses Return after pasting.

### 4.2 Modes
A mode combines a preset (Voice to text, Message, Email, Note, Custom prompt), a language, a voice model, a cleanup level (Off; Clean up, which runs S1-mini on device and is the default; Rewrite, which runs an Ollama model with the preset's instructions), a tone from casual to formal, a text model picker (S1-mini for Clean up, any Ollama model for Rewrite), a Prose/Lists structure switch for Clean up, app and website triggers, a shortcut, and advanced options (autocapitalize, auto paste, auto send). The default mode's voice model is the app-wide default that other modes inherit. Custom instructions are only shown under Rewrite, since S1-mini does not follow instructions. S1-mini is English only: a mode pinned to another language pastes the raw transcript; long dictations are normalized in sentence-aligned chunks; filler-only dictation pastes nothing. Modes switch automatically by front app or site, by shortcut, or through the mode switcher (default ⌥⇧K).

### 4.3 Models library
Table of voice models (Cohere Transcribe, Canary 1B v2, Parakeet V2/V3/110M/Japanese, Whisper Large v3 Turbo, Apple Speech, imported GGML files) and text models (S1-mini, Ollama models) with type, speed and accuracy meters, size and download progress. Download, show in Finder, delete, import; which model is used is chosen per mode under Modes. Provider filter, search.

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
| Agent Panel | Connect Claude Code and Codex; panel position (Bottom, Center, Top; always horizontally centred), sound, auto-send, hide duration, preview; per-project mute |
| Configuration | Appearance (theme, recording window, always show, pill position), Keyboard Shortcuts, Application, Advanced settings (Dock, voice model active duration, app folder, clipboard and paste) |
| Sound | Recording toggles, playback behavior (Pause reads and controls the system Now Playing item through the vendored MediaRemoteAdapter; Mute silences the output device, falling back to volume zero on devices without a mute control), sound collection (start/stop pair) and volume |
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
- Permissions: Microphone, Accessibility; Apple Events for browser URL detection (Modes). App Sandbox disabled. A guided Permissions window (menu bar > Permissions..., Home banner, onboarding, and automatically at launch when something is missing) shows both with live status and one button each: Microphone triggers the system Allow dialog, or opens the Microphone pane when access was turned off; Accessibility fires the system prompt and opens the Accessibility pane, and when this copy was trusted before (a rebuilt or updated app) it drops the stale entry first so the switch works the first time. The window closes itself once both are granted. Recording with Microphone turned off opens the guide instead of recording silence.
- Updates: Sparkle, feed at `appcast.xml` in this repository.

## 7. Non-goals

- Cloud transcription or cloud LLM providers.
- iOS, Windows, Linux.
- Paid features, licensing, telemetry.
- Proprietary third-party models that cannot be redistributed.

## 8. Status

All phases of `PLAN.md` are implemented. Remaining: prune the cloud LLM providers left inside `AIService`, remove the iOS targets from the project, notarized release builds, Sparkle signing key and appcast publishing.

Messages adds separate history/sending permissions and reviewed iMessage sending. Create Prompt in the chat Add menu retains numbered images while editing or refining a draft with the selected chat model. These paths have fixture checks; live account and permission testing remains outstanding.
