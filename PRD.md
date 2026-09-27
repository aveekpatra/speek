# Speek: Current product requirements

Updated: 2026-09-26.

## Current direction

Speek is a cloud-connected macOS voice-to-action assistant. Users can dictate into the current app, rewrite selected text, ask questions with screen/file context, and request actions through connected tools. The application combines a persistent notch assistant with in-app Tasks, Memory, Models & Voice, Integrations, and Settings.

The current feature inventory and remaining limitations are in [docs/FEATURE_STATUS.md](docs/FEATURE_STATUS.md). That document distinguishes implemented source paths from live-tested capabilities. Neither this PRD nor a passing build establishes full VoiceOS parity or production readiness.

## Current workflows

- Dictation: hold the shortcut, or opt into double-tap hands-free capture; transcribe, apply corrections and the selected writing mode, then insert only into the captured valid destination. Preserve text when delivery is unsafe.
- Edit: explicitly enable selected-text editing, capture the selection, speak the edit, and replace only if the original selection still matches.
- Agent: capture fresh permitted context, select a connected tool, validate arguments, review consequential actions, execute and report the actual result. Continue dependent steps within execution limits.
- Integrations: configure MCP servers (2026-07-28: plugin questions and model requests are answered in the notch and the request retried), supported native apps (including a Spotify account for search, library, playlists and queue), trusted CLI manifests, scoped dictation hooks and local instruction skills. Unavailable services must not be represented as connected.
- Coding assistants: hooks only (Integrations > Local tools). Speek never starts coding tasks; it shows the reply panel and routes typed or dictated answers back to the session.
- Settings ownership: Each setting has one home. Models & Voice: accounts, default provider/model/reasoning for new chats, voice connection, dictation and speech models, voice, spoken replies and speaking speed. Settings: General (speak shortcut, double-tap hands-free, screen context, launch at login), Dictation (microphone, recognition language, vocabulary hints, writing mode and style, Edit Mode), Privacy (save history, recording recovery), Permissions (Microphone, Accessibility, Screen Recording). Memory: Facts, Episodic, Procedural, Vocabulary (names, terms, corrections, spoken shortcuts). Integrations: Plugins, Native apps (Calendar, Reminders, Mail, Notes, music, Messages, Files working folder), Local tools (Codex and Claude Code, CLI manifests, hooks), Skills. App-specific macOS access is requested from its integration card.
- Sessions and background requests: the notch continues the current conversation within 10 minutes of the last turn, or within an hour when the request refers back ("it", "that"); otherwise it starts a new one, and the notch header shows which conversation you are in. The main window always continues the thread you opened. Asking something new while a quick request is working queues the new one right after it, in the foreground; computer use runs in the background and reports back with a notice. Switching conversations while a request works moves it to the background. Notch requests include a screenshot of the display taken when the request starts (can be turned off); circling something while holding the agent shortcut sends it with the circle drawn on it; screen.capture takes one on demand.
- Voice activation (off by default): "Hey <name>" (name set in Settings > General) is recognized on device with SpeechTranscriber; it starts an agent request that ends after 1.4 s of quiet, or cancels if nothing is said within 6 s. Listening pauses while recording or reading a reply aloud.
- Memory: maintain explicit facts, dated completed-request/result episodes, user-authored procedures and transcription corrections, including corrections learned from edits made right after a dictation (shown under the notch with Undo). Respect history opt-out and allow inspection, editing and removal.
- Navigation: Sidebar: New task, a Scheduled group (only when a schedule exists or a scheduled request is ready to review), and Recents. There is no Activity page and no coding task page: background work reports in the notch and in its source chat. Dictation history opens from the notch and menu bar menus (Recent Dictations, one-click copy) and from Settings > Dictation. Coding assistants connect through hooks only: Speek shows a reply panel when Claude Code or Codex finishes, asks, or needs permission, and never runs coding tasks itself. Main menu: File (New Task, New Schedule), View (sections, Dictation History), Voice (speak, type, circle, recent dictations, reply to coding assistant, stop tasks), Help. The status item shows idle, listening, or needs attention, with quick actions and anything waiting. Schedules create a request to review in a new chat while Speek is running; they do not grant permission for external writes.
- Recovery: optional local audio backup, bounded by age/count/disk size, for retry and copying. Keep it off by default and disable new backups when history saving is off.

## Design and acceptance requirements

Preserve the established notch design. In-app screens use the current settings background, consistent type hierarchy, compact flat action buttons beside section headings, shared card surfaces, responsive grids and right-aligned controls. Reuse existing model controls and actual provider identities.

Each feature needs real persistence and error handling, cancellation where work is asynchronous, and a reachable empty/loading/error state. Do not show fake success, silently reset user selections, hide unsupported behavior behind placeholder buttons, or claim completion without a tool result. Missing credentials or account permissions must be explicit.

Verification includes source helper checks, a signed app build, and permission/account-dependent manual checks. Retain the stable Speek Dev Signing identity and canonical Applications install. Production release requires the outstanding tests and implementation gaps recorded in FEATURE_STATUS.md to be resolved or explicitly scoped out.

## Current boundaries

Speek uses cloud speech and request providers; local model downloads and on-device inference are not part of the product. Subscription request authentication and speech API credentials remain separate. Speek is macOS only: there are no mobile, Windows, or other cross-platform clients. Rich integration widgets and enterprise services are not implemented.
