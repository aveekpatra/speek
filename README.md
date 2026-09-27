# Speek

Speek is a cloud-connected voice assistant for macOS. Dictate into the focused app, edit selected text by voice, or ask an agent to use connected tools with screen and file context.

## Current application

- Global hold-to-speak shortcut, optional double-tap hands-free capture, and a persistent notch assistant.
- Raw, Light, and Polished dictation; destination-aware writing styles, saved replacements, language hints, microphone selection, and focus-checked insertion.
- Selected-text Edit Mode, local dictation history and estimates, JSON export, and opt-in temporary recording recovery.
- Chats with provider/model/reasoning defaults, screen and circled-region context, image/PDF/text attachments, and reusable prompts.
- Reviewed tool execution for web research, working-folder files, Calendar, Reminders, Mail, Notes, Apple Music, and Spotify.
- Local and remote MCP servers, imported CLI tools, scoped dictation hooks, and local instruction skills.
- Explicit facts, dated request/result episodes, and user-authored procedures with search and editing.
- Sidebar: New task, a Scheduled group (only when a schedule exists or a scheduled request is ready to review), and Recents. There is no Activity page and no coding task page: background work reports in the notch and in its source chat. Dictation history opens from the notch and menu bar menus (Recent Dictations, one-click copy) and from Settings > Dictation. Coding assistants connect through hooks only: Speek shows a reply panel when Claude Code or Codex finishes, asks, or needs permission, and never runs coding tasks itself. Main menu: File (New Task, New Schedule), View (sections, Dictation History), Voice (speak, type, circle, recent dictations, reply to coding assistant, stop tasks), Help. The status item shows idle, listening, or needs attention, with quick actions and anything waiting.
- Each setting has one home. Models & Voice: accounts, default provider/model/reasoning for new chats, voice connection, dictation and speech models, voice, spoken replies and speaking speed. Settings: General (speak shortcut, double-tap hands-free, screen context, launch at login), Dictation (microphone, recognition language, vocabulary hints, writing mode and style, Edit Mode), Privacy (save history, recording recovery), Permissions (Microphone, Accessibility, Screen Recording). Memory: Facts, Episodic, Procedural, Vocabulary (names, terms, corrections, spoken shortcuts). Integrations: Plugins, Native apps (Calendar, Reminders, Mail, Notes, music, Messages, Files working folder), Local tools (Codex and Claude Code, CLI manifests, hooks), Skills. App-specific macOS access is requested from its integration card.

This is an implementation in active verification. It is not full VoiceOS feature parity or a claim of production readiness. [Feature status](docs/FEATURE_STATUS.md) records the supported paths, limits, and remaining work. Older architecture documents describe earlier stages and may not reflect current behavior.

## Setup

Open the app's Models & Voice page to connect a request provider and a separate voice API connection. Existing Codex login or ChatGPT subscription authentication does not provide general speech API access. Enable native services or connect external tools under Integrations. Choose a working folder before file or coding actions.

macOS permissions depend on the feature: Microphone, Accessibility, Screen Recording, Calendar, Reminders, and Automation for native app scripting. Live provider calls, account-specific actions, and permission-dependent flows still require testing with the user's configuration.


Messages adds separate history/sending permissions and reviewed iMessage sending. Create Prompt in the chat Add menu retains numbered images while editing or refining a draft with the selected chat model. These paths have fixture checks; live account and permission testing remains outstanding.

## Build and verification

Use Xcode 26 and the Speek scheme. Read the deployment target from `Speek.xcodeproj`.

```sh
./scripts/dev-build.sh
python3 scripts/checks/check_voice_features.py
python3 scripts/checks/check_runtime.py
python3 scripts/checks/check_integrations.py
python3 scripts/checks/check_local_plugins.py
python3 scripts/checks/check_native_activity.py
python3 scripts/checks/check_attachments.py
python3 scripts/checks/check_coding_tasks.py
```

The checks compile production helpers with fixtures. They do not establish live API compatibility, successful TCC permissions, or final visual quality. See the feature status document for the manual verification matrix.

Keep the stable `Speek Dev Signing` identity and canonical `/Applications/Speek.app` installation. The development script refuses to substitute ad-hoc signing, because changing identity can invalidate macOS permissions. Do not launch an unsigned verification build as the installed app or reset TCC to work around a build failure.

## Credits and license

Speek is derived from Whisper Pro by Zdenek Culik and VoiceInk by Prakash Joshi Pax. Their GPL-3.0 license and attribution remain. Avo by Aristu Sachdev was studied as an interaction reference; its source was not copied. See the repository license files for details.
