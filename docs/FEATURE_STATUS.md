# Speek feature status

Updated: 2026-09-26.

This inventory describes current source wiring, not a certification of production readiness. The comparison baseline is [the VoiceOS research map](../../voiceos-feature-map.md), which itself documents public claims rather than verified competitor behavior. Missing account credentials are only one class of remaining work; unsupported features below still require implementation.

## Current navigation and design contract

The main destinations are Tasks, Memory, Models & Voice, Integrations, and Settings. Tasks provides shared Activity and schedules, prompts, and attachment actions. Integrations separates Plugins, Native apps, Local tools, and Skills.

Codex and Claude Code are integrations configured under Native apps. A coding request opens a review sheet for its request, engine, folder, and supported options. Its progress and result appear in shared Activity. There is no separate Coding tasks destination or coding workspace in the product navigation.

Use the existing settings background, shared settingsSurface cards, compact flat action buttons, consistent typography, and trailing controls. The established notch geometry and main navigation styling are not invitations to redesign those surfaces during feature work.

## Implemented paths and boundaries

| Area | Implemented | Important boundary |
|---|---|---|
| Dictation | Cloud transcription, focus-checked paste, Raw/Light/Polished, destination formatting, writing style, persisted phrase replacements. | Polishing uses a cloud text call. A failed polish preserves the corrected original and reports a warning. Model accuracy is not established by local tests. |
| Edit Mode | Opt-in spoken rewrite of selected text, with original element/text/range captured before recording. | Replacement is allowed only while the same selection remains valid. Otherwise the result is retained for copying. |
| Capture | Actual AudioDeviceManager selection, system default, recognition-language hints, optional double-tap hands-free, 19-minute warning and 20-minute finish. | No wake word or full-duplex speech. The hands-free option preserves normal holds; very short taps wait briefly for a second tap. |
| Long recordings | Oversized audio is split before cloud transcription and assembled afterward. | No claim of unlimited length, perfect chunk continuity, or live streaming partial transcripts. Provider quotas and timeouts still apply. |
| Vocabulary | Saved correction/replacement entries apply locally. Supported OpenAI models receive bounded sanitized terms and language fields; OpenRouter receives its supported language field. | OpenRouter's generic prompt field is documented as ignored, so generic vocabulary hints are not falsely advertised there. No automatic dictionary learning or shared vocabulary sync. |
| Dictation history | Search, copy, delete, clear confirmation, JSON export, word/session totals, recorded minutes, estimated time saved. | Local only, latest 500 entries. Estimates use 40 words/minute minus recording time, not measured productivity or percentile rankings. |
| Recording recovery | Explicit opt-in, owner-only local audio/index, retries with Copy result, 24-hour expiry while running, maximum five recordings and 100 MB. | Disabled when history saving is off. Successful delivery removes backup. Expiry cannot run while the app is closed; cleanup occurs on next launch. No automatic retry paste into another app. |
| Screen context | Current app, selected text, screenshot, and circled-region context. | Screen understanding does not implement arbitrary UI control. Context can contain stale or incomplete accessibility data and must be treated as untrusted. |
| Attachments | Images, text, and text-bearing PDFs; multiple attachments, previews, context extraction, and image forwarding. | Eight files, 10 MB each, 30 MB combined. Extracted text is bounded; encrypted/scanned PDFs can require screenshots. Not a general document conversion or export system. |
| Prompts | Local reusable prompts, variables, search, favorites, edit/delete, explicit field-filling sheet. Create Prompt includes editable context, numbered image previews, refinement with the selected chat model, undo and draft insertion. | Copy text copies text only. Original attachments remain when using the prompt in chat. No annotation editor or multi-file export bundle. |
| Computer use | Foreground requests can launch an actual Codex App Server turn with the installed native Computer Use plugin. Progress, cancellation, app-consent prompts and final results return to Speek. | Currently requires Codex on this Mac, its signed-in account, and a working Computer Use plugin. No automatic model upgrade. Native plugin restrictions still apply, including its exclusion of ChatGPT itself. |
| Browser actions | Computer-use turns receive the installed Ego Browser skill and explicit instructions to use Ego for browser work. | No embedded browser or Codex in-app browser. Ego installation and authenticated sessions remain user-owned. Browser end-to-end verification is tracked separately below. |
| Agent execution | Connected tool catalog, schema validation, iterative tool/result loop, editable review before consequential actions, cancellation and bounded execution. | Requires the selected model to route correctly. A reviewed action is not authorization for unrelated later actions. Local fixtures do not prove all model/provider combinations. |
| Web research | Public search results with URLs, bounded HTTPS page reads, model source instructions, local/private address restrictions. | Bing RSS and basic HTML extraction can fail or omit JavaScript content. No logged-in browser browsing, dedicated maps/weather/finance tools, or rich media previews. |
| Working-folder files | List, file details, recent files, filename search, UTF-8 read, create folder/file, append, copy, move/rename, Trash, and open. | Restricted to the configured folder, with symlink/path checks and size/result limits. Not all Finder or attached-file operations. |
| Calendar | Calendar listing, event search, availability intervals, create/update/delete reviewed events. | EventKit permission required. Availability covers accessible calendars, not arbitrary attendees. Event creation does not invite attendees; recurring edits target an occurrence. |
| Reminders | Lists, search, create, complete/reopen, and delete. | EventKit permission required; not every Reminders feature or recurrence editor. |
| Apple Mail | Recent Inbox subject/sender search, message read, draft, explicit reviewed send, and reply draft. | Search covers the most recent 200 Inbox messages; no full-mailbox/content search or mailbox moves. Send targets one address through the default Mail account. Reply creates a draft. |
| Apple Notes | Bounded title search, plain-text read, create, append. | No full notes search index, rich embedded content, folder manager, or general note editor. |
| Messages | Recent iMessage conversations, readable-text search, unread messages, conversation reading, reviewed send to an exact phone/email. Separate read and send opt-ins. | History requires Full Disk Access and a supported local schema. Rich attributed bodies and attachments are not decoded. Sending requires existing iMessage sign-in and Automation permission; submission is not delivery confirmation. |
| Music | Apple Music and Spotify status, play/pause, next/previous, volume. | Local app scripting, not catalog search, queue/library/playlist management, remote-device control, or live artwork cards. |
| Coding integrations | Codex/Claude Code executable discovery, reviewed requests, selected workspace, persisted jobs, progress/result, cancellation, session continuation, queued/parallel work subject to folder overlap. | Engine flags and permissions differ. Unsupported permission requests are not silently bypassed. No general diff editor, external-session import, or full interactive CLI parity. |
| MCP | Local stdio and remote HTTP server connections, discovery, tool enable/disable, reviewed execution, saved settings and Keychain secrets. | No complete managed OAuth login/refresh, resource/prompt browser, elicitation UI, sampling implementation, or hosted integration service. Real servers require compatibility tests. |
| Local tools and hooks | Imported validated CLI manifests, direct executable invocation, tool schema review, bounded output/time, explicitly enabled app-scoped dictation hooks. | Executables are trusted local code, not sandboxed third-party widgets. No full transcript/tool/completion hook suite or automatic plugin authoring. |
| Skills | Imported local instruction files, enable/disable, request-context inclusion. | Supporting scripts are not automatically executed. No marketplace, package updater, or remote distribution system. |
| Memory | Explicit facts, dated completed-request/result episodes, user-authored procedures, search/edit/delete and bounded relevant recall. | No inferred personal facts, vector retrieval, automatic procedural learning, imported knowledge base, or cloud/team synchronization. History opt-out stops episode recording and recall, but keeps existing entries. |
| Activity | Persisted background requests and coding jobs, progress/results/errors, cancellation/retry and interrupted-state handling. | Work does not continue after app termination. Interrupted tasks require review rather than blind replay. General background work is bounded and sequential. |
| Schedules | Once/daily/weekly, time-zone-aware recurrence, pause/delete, notifications, due requests and review. | Speek must be running. Accepted chat handoffs are recorded separately from completed actions so later occurrences remain eligible. Due requests wait for review; this is not unattended recurring email sends or arbitrary cron. Missed repeats are combined. |
| Speech output | Configured speech model/voice, preview, read-aloud, stop and playback speed. | No synchronized word highlighting, continuous conversation, automatic barge-in, or complete media ducking/cue parity. |
| Foundation | Chat pin/archive/delete, defaults snapshots, permissions pages, launch at login, current provider and voice settings. | macOS only. No Windows/mobile release, enterprise administration, team billing, SSO, shared libraries, or commercial trial system. |

## Missing product capabilities

These are not solved by supplying API keys alone:

1. Direct first-party OAuth integrations for Gmail, Google Calendar/Drive/Docs/Sheets/Maps, Slack, Outlook/Teams, Linear, Jira, Notion, Canvas, and X. A user-supplied MCP server may expose some services, but that is not a built-in tested connector.
2. Full Messages rich-text/attachment support; a dedicated Obsidian integration; advanced Finder, Mail, Notes, Calendar, and music actions described in the competitor map.
3. Rich domain-specific result/confirmation cards, maps, charts, image/video previews, live media controls, sandboxed HTML widgets, and a Widget Kit.
4. Integration Studio, AI plugin generation, branded package distribution, hosted runtimes, fast intent routing, and the full integration hook lifecycle.
5. MCP OAuth and advanced server capabilities, plus compatibility coverage beyond local fixtures.
6. A standalone Mac-control backend independent of the installed Codex Computer Use plugin, and computer use through OpenRouter or the isolated subscription profile. Current UI automation uses the local Codex plugin.
7. Live partial transcription, surrounding-text vocabulary adaptation, automatic correction learning, bulk dictionary import, multilingual enabled-language sets, and mouse-button triggers.
8. Annotation editing, image-bundle export and direct voice invocation for Create Prompt. The current flow starts from the chat Add menu.
9. Continuous conversational speech, word highlighting, robust interruption/turn-taking, and full capture cues/media behavior.
10. Cloud continuity across machines, team features, managed security controls, mobile/Windows apps, and service operation while Speek is closed.

## Verification commands

Run from the `app` directory:

```sh
python3 scripts/checks/check_voice_features.py
python3 scripts/checks/check_runtime.py
python3 scripts/checks/check_integrations.py
python3 scripts/checks/check_local_plugins.py
python3 scripts/checks/check_native_activity.py
python3 scripts/checks/check_attachments.py
python3 scripts/checks/check_coding_tasks.py
python3 scripts/checks/check_messages.py
python3 scripts/checks/check_create_prompt.py
python3 scripts/checks/check_computer_use.py
./scripts/dev-build.sh
```

The source helper checks exercise real implementations with fixtures, fake audio, temporary storage, local transport processes, or script compilation. They cover state transitions, validation, persistence, privacy settings, file boundaries, retention, and protocol behavior. Passing them does not verify provider credentials, remote compatibility, real microphone quality, actual app permissions, visual layout, or delivery into every editor. A current signed app build and live UI walkthrough remain separate gates.

## Live verification still required

- Actual OpenRouter/OpenAI speech and text calls with chosen models, quotas, long recordings, error recovery, language hints, and voice playback.
- Codex subscription/authentication refresh, actual Codex/Claude CLI versions, request review, session continuation, denied permissions, and cancellation against disposable workspaces.
- Microphone selection/unplugging, hands-free timing, record startup/release races, secure fields, stale selection, focus changes, real dictation insertion, and recovery cleanup across relaunch.
- Messages history permission and supported schema, Automation consent, existing iMessage sign-in, and explicitly authorized sending to a test recipient.
- Calendar/Reminders permission grants and disposable records; Automation consent for Mail/Notes/Music/Spotify. Do not test outbound mail by sending without explicit user authorization.
- User-supplied HTTP and stdio MCP servers, credentials, reconnection, disabled tools and errors; local executable manifest setup and scoped hook behavior.
- Background scheduling across daylight saving, sleep/wake, app quit/relaunch, notification denial, review resumption, and duplicate-action prevention.
- Narrow and wide windows, empty/populated/error states, VoiceOver labels, keyboard navigation, and Reduce Motion/Transparency. Current source styling is not evidence of a completed visual QA pass.

## Privacy and signing

Conversation/episode and dictation-history settings govern those stores; they are not a blanket promise that all operational job, schedule, or integration metadata disappears. Recording recovery has its own default-off toggle and also respects history opt-out. Prompts, facts, procedures, and integration configuration remain explicit local records until removed. Cloud requests send their included text/context to the selected provider. Provider retention and training policies are external to Speek.

Keep `Speek Dev Signing` and the canonical `/Applications/Speek.app` identity. `scripts/dev-build.sh` refuses to substitute ad-hoc signing, signs and verifies the bundle, and refreshes the installed copy when present. Unsigned compile verification is not an installable replacement. Do not change signing identity or reset TCC as a routine test step.

## Relevant source

- `Speek/Assistant/AssistantController.swift`: capture, dictation delivery, context, agent loop and feature wiring.
- `Speek/Runtime/`: tool registry, file/web actions, scheduling, background requests and prompts.
- `Speek/Integrations/`: MCP transport/store, local executable plugins and hooks.
- `Speek/Actions/NativeOrganizerTools.swift`, `NativeAppTools.swift`, `CodingTaskManager.swift`: native and coding integrations.
- `Speek/Assistant/`: feature screens, memory, capture preferences, history/recovery, prompts and attachments.
- `scripts/checks/`: reproducible helper verification. XCTest/Testing source files are also under `SpeekTests`; target registration and full test-suite health are separate from these helper commands.

## Computer-use verification (2026-09-26)

- A standalone app-server process, with this development chat's CODEX environment removed, discovered and invoked the native Computer Use plugin.
- Installed Speek routed a chat request through GPT-6 Sol, opened Calculator, pressed its controls for 17 x 23, and returned 391. An independent accessibility read confirmed the expression and result in Calculator.
- An inline consent card was observed in the installed app. Routine low-risk Computer Use consent is now reusable for one task after selecting Allow this task. Sensitive, unknown, and non-Computer-Use approvals do not inherit that grant. The grant expires with the task.
- Local fixtures cover JSONL framing, RPC failures, process exit, cancellation, task consent reuse, sensitive consent, and consent reset between tasks.
- Live microphone-to-action and authenticated Ego workflows still require separate verification. These results do not establish arbitrary-app success.

### Asynchronous computer tasks

Computer requests hand off to `ComputerTaskManager` after routing, releasing the live
assistant's busy state. Each queued request captures its context, provider, model,
reasoning and source chat. Computer jobs serialize access to the desktop; coding
jobs retain their separate two-worker queue. The Tasks screen shows progress,
per-job cancellation, permission requests and expandable results. Completions write
to their source chat and add a separate result notice to the main chat and notch.
Announcements wait for foreground work and dictation to finish, then honor the
spoken-replies preference or play a short completion sound.
Cancelling dictation no longer cancels computer work. Jobs waiting for permission
remain independent of foreground input. Computer job records are session-only;
completed results remain in saved chat history when history is enabled.

Checks: `ComputerTaskChecks.swift` verifies foreground concurrency, desktop queue
ordering, source identity, queued/running cancellation and queue recovery.
Existing coding and computer approval/transport checks also pass.

Installed-app verification: a GPT-6 Sol computer task calculated `9 x 7` in
Calculator while Speek accepted and answered another foreground request during
its permission wait. The microphone remained enabled. The task subsequently
completed into its source chat and job card; Calculator's live accessibility
value independently confirmed `63`. Actual microphone recording during active
mouse/keyboard automation still requires user testing. Shared desktop actions
can change focus; the existing dictation target validation/recovery still applies.

Completion notice follow-up: both computer and coding results now use a shared
notice with request, result preview, View result and dismissal. View result opens
the originating chat when available. The build and stable-signature installation
passed. Live notification/audio verification remains pending because the user
was actively recording during the installed-app check.
