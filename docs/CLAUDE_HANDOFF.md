# Speek: macOS implementation handoff

Prepared 2026-09-26. Audience: Claude continuing this repository.

## 1. Objective and evidence rules

Finish Speek as a reliable macOS voice-to-action assistant for the owner's daily use. VoiceOS's documented Mac features are the comparison baseline, not a requirement to copy its business, branding, every architectural choice, or other platforms.

Checklist convention:

- [x] The implementation exists. This is NOT a claim that it is fully verified or production-ready.
- [ ] A concrete gap, unresolved decision, or verification task remains.
- An unchecked item requiring new credentials, an account, product judgment, or current policy verification says so explicitly. Do not fabricate support to close a checkbox.

Evidence order:

1. The owner's latest instructions and the decisions below.
2. Current executable source and observed installed-app behavior.
3. Current feature inventory and test results.
4. Older design/architecture documents, which contain superseded directions.

Read `../voiceos-feature-map.md` from the repository root for the full recorded competitor research, action lists and source URLs. It records public claims inspected through Ego Browser, not hands-on verification of VoiceOS. No new competitor verification was performed for this handoff.

Read `docs/FEATURE_STATUS.md` for implementation boundaries. Its early navigation paragraphs are stale: Coding tasks is now a separate subpage, and Activity no longer lists coding jobs. Later computer-use and asynchronous-execution notes are newer. `docs/VOICE_ACTIONS.md` explicitly contains historical provider/fallback text. `ui-registry.md` contains several generations of design. Do not restore old instructions over the current decisions below.

## 2. Product and business decisions: preserve these

- [x] macOS ONLY, deliberately. Windows, Android, iPhone and cross-platform work are not missing features. Do not propose or implement them for this task.
- [x] Personal-use-first, intended to be open source. The owner is not operating a paid hosted assistant service and does not intend to fund other users' LLM subscriptions.
- [x] Users bring their own Codex installation/account and optional API credentials. Missing local Codex is an explicit dependency/setup state, not a reason to build a new computer-use engine now.
- [x] Build computer use on Codex for now. A provider-independent runtime was considered and deferred to avoid duplicating Mac automation infrastructure before the core product works.
- [x] The central promise is voice-to-action inside real apps and authenticated websites. Opening an app or describing a screenshot is not completion of an interaction task.
- [x] Use Ego Browser and its installed skill for browser automation. Reuse the user's signed-in browser context.
- [x] Do not add an embedded browser, Codex in-app browser, Playwright/CDP fallback, or browser automation through native CUA. The owner's reason is practical authentication and separation of the browser from the coding environment.
- [x] Models & Voice owns accounts/providers, default task provider/model/reasoning, and audio models/voices. Integrations owns MCP servers, native app adapters, local CLIs/hooks and skills. These are different concepts and different screens.
- [x] Default provider/model/reasoning are explicit and persistent for new chats. Existing chats retain their snapshots. Do not silently upgrade a simple task to Astra or switch billing providers.
- [x] The owner requested GPT-6 Luna as the inexpensive default direction. Verify current account/provider availability and defaults in source. Sol was selected for the successful live tests; that is not authorization to make Sol or Astra the universal default.
- [x] Dictation and speech output need independently valid audio models and discoverable human-readable voice choices. Do not ask users to find and paste provider slugs. Do not assume a text model can transcribe or synthesize audio.
- [x] Native computer jobs must run independently of dictation and foreground requests. They serialize access to the shared desktop. Coding jobs have a separate queue with up to two non-overlapping project jobs.
- [x] One explicit approval may cover subsequent routine low-risk computer-use consent for that task. Do not nag at every ordinary action. Sensitive/unknown requests still have separate review, and the grant expires with the task.
- [x] Permission requests must be visible in Speek. Never leave an invisible modal/server approval holding a job forever.
- [x] Completed work must return to the originating chat and visibly announce itself in the main UI/notch. Announcements wait for dictation/foreground work to finish. They honor the spoken-replies setting, otherwise use a short sound.
- [x] Coding assistants are integrations, not a reason to turn every app action into a coding job. Coding history has one dedicated sidebar destination.
- [ ] Resolve Claude Code authentication/billing policy before claiming subscription coverage. The owner explicitly questioned whether programmatic CLI usage incurs extra charges. Existing source launches a CLI subprocess; CLI discovery/sign-in does not prove billing entitlement. Verify current official Anthropic policy and actual credential mode. Do not assume API-key and subscription authentication are equivalent.
- [ ] Keep coding shortcuts only where they genuinely dispatch reviewed CLI tasks. If using integration hooks instead, do not add redundant coding-task shortcuts. The owner's choice was conditional on the policy/architecture finding, not blanket approval for both.
- [x] External-display notch fallback is not a priority for this owner's use case. Keep reasonable behavior, but do not expand scope around it.
- [x] Enterprise billing, seats, SSO, commercial trials, customer accounts and team sync are outside the current personal Mac product scope.
- [x] Provider privacy/retention is external to Speek. Do not market cloud processing as offline, zero-retention, or universally excluded from training without evidence.

## 3. Non-negotiable design decisions

- [x] Keep the existing Mac shell: left icon rail, task sidebar, content pane and the separate global notch assistant.
- [x] Activity and schedules, Dictation history, and Coding tasks are chat-area subpages. The task sidebar stays visible; only the chosen destination is selected. No modal overlay or full-shell replacement for these destinations.
- [x] Activity has Jobs and Schedules only. Coding history is not duplicated there. Coding configuration under Integrations is still valid; configuration and job history serve different purposes.
- [x] Memory and Integrations use consistent tabbed layouts, cards/grids where appropriate, matching settings backgrounds and progressive disclosure.
- [x] Memory has Facts, Episodic, Procedural and Vocabulary. The third fundamental memory category the owner asked about is Procedural. Vocabulary (formerly Corrections, merged with Settings > Replacements) is a separate practical transcription feature.
- [x] One setting, one home (2026-09-26 consolidation). Each setting has one home. Models & Voice: accounts, default provider/model/reasoning for new chats, voice connection, dictation and speech models, voice, spoken replies and speaking speed. Settings: General (speak shortcut, double-tap hands-free, screen context, launch at login), Dictation (microphone, recognition language, vocabulary hints, writing mode and style, Edit Mode), Privacy (save history, recording recovery), Permissions (Microphone, Accessibility, Screen Recording). Memory: Facts, Episodic, Procedural, Vocabulary (names, terms, corrections, spoken shortcuts). Integrations: Plugins, Native apps (Calendar, Reminders, Mail, Notes, music, Messages, Files working folder), Local tools (Codex and Claude Code, CLI manifests, hooks), Skills. App-specific macOS access is requested from its integration card.
- [x] Section actions belong near their headers, right aligned. Use compact flat buttons, not oversized glass capsules. Do not reinterpret 'larger' as a giant call-to-action.
- [x] Sidebar labels are now 15-point regular system text, icons 15 points in an 18-point column, section labels 13 points. New task, destinations, search and recent chats should remain consistent.
- [x] New task has a subtle background. Search spans the same horizontal area as recent rows. The archive control is trailing aligned.
- [x] Chat overflow controls appear on hover. When hidden, they must not reserve space and truncate titles prematurely.
- [x] Model selectors fit their content and align to the right. Use consistent dropdown treatment for text models, transcription, speech and voices.
- [x] A selected item uses `checkmark.circle.fill`, not a bare tick.
- [x] Model chips display a readable model name followed by the real provider icon. No provider-name text, reasoning label, raw slug or decorative sparkle in the chip. Reasoning remains selectable inside the model UI.
- [x] Codex, ChatGPT and OpenRouter require distinct real logos. Assets already exist. Do not substitute generic SF symbols for brand marks.
- [x] Unavailable provider choices are grey with a lock before the label. No redundant Connections link at the top of the selector.
- [x] Memory uses `point.3.connected.trianglepath.dotted` inactive and `point.3.filled.connected.trianglepath.dotted` selected. Preserve consistent outline/filled navigation states.
- [x] The owner meant Apple's intrinsic SF Symbol drawing effects, not arbitrary rotation, bounce or view transitions. Do not add decorative motion as a substitute. Respect Reduce Motion.
- [x] The resting notch is pitch black and uses both sides of the physical camera notch, without extra vertical space. Keep the accepted top/bottom shape; repeated redesigns caused regressions.
- [x] Expanded glass gradually emerges below the camera strip. Fade stops must scale with available body height; coincident stops caused a hard black edge in short error panels and were fixed.
- [x] Keep status controls in the notch wings. Avoid unnecessary status text such as 'Needs attention' consuming a separate header row.
- [x] Composer sits near the bottom with balanced side/bottom insets and concentric corner nesting. Do not leave a large empty bottom gutter.
- [x] App context must reflect the actual focused app; use Finder on desktop. Do not retain stale Claude labels while ChatGPT is focused.
- [x] Resting agent mode uses the requested sparkle symbol; dictation uses waveform. The circled microphone was rejected. Existing icons were enlarged only slightly.
- [x] Dictation recording should not show an agent text composer. Copy dictation appears for failed insertion/recovery, not after every command, and must not be duplicated.
- [x] No generic chat bubbles, excessive cards, duplicated destinations or new visual systems just to implement a feature.

## 4. Implementation checklist: voice and writing

### Capture and delivery

- [x] Hold-to-talk and optional double-tap hands-free capture.
- [x] Cloud transcription and insertion into a captured target with focus/selection checks.
- [x] Microphone selection and system-default device selection.
- [x] Recognition-language hints where supported by the provider.
- [x] 19-minute warning and finish at 20 minutes; oversized audio chunking.
- [x] Clipboard/paste delivery path and retained text when insertion cannot safely happen.
- [x] Opt-in local recovery audio: maximum five recordings/100 MB, 24-hour expiry, retry with Copy, remove on successful delivery. Cleanup after time away occurs on relaunch.
- [ ] Enabled-language sets and robust automatic multilingual handling. Do not promise an exact language count across providers without checking capabilities.
- [ ] Configurable mouse-button triggers and full shortcut termination/reset behavior.
- [ ] Warm-capture behavior, consistent start/stop/error cues and media ducking/restoration.
- [ ] Live partial transcripts. Current recording transcription is not continuous streaming.
- [ ] Verify long-recording chunk continuity, quota/timeouts, device unplugging and startup/release races.
- [ ] Verify dictation during active computer clicking. Asynchronous execution releases Speek's busy flag but does not isolate OS focus. Preserve target checks and recovery; never paste into a different app after focus changes.

### Writing quality and vocabulary

- [x] Raw, Light and Polished output.
- [x] Destination-aware formatting and writing preferences.
- [x] Persisted phrase replacements and vocabulary entries applied locally.
- [x] Bounded supported vocabulary hints for OpenAI; supported language field for OpenRouter. Do not claim OpenRouter's ignored generic prompt field tunes recognition.
- [x] Spoken rewriting of a captured selection; replace only if the original selection is still valid.
- [ ] Surrounding-text and visible specialist-term adaptation before transcription.
- [ ] Automatic vocabulary learning from explicit corrections, with review and undo.
- [ ] Bulk dictionary import and AI-assisted onboarding suggestions.
- [ ] Dictionary updates learned from Edit Mode corrections.
- [ ] Full output-quality evaluation for punctuation, grammar, lists, number formatting, filler removal and false starts. These rely on models; source code alone is not accuracy proof.
- [ ] Cross-device dictionary sync is deferred for the personal local Mac scope unless the owner requests it.

## 5. Implementation checklist: context and assistant work

- [x] Typed/spoken requests, retained messages and follow-up context.
- [x] Current app, selected text, screenshot and selected-region capture.
- [x] Screen context treated as untrusted evidence, not instructions/authorization.
- [x] Multiple image/text/text-bearing-PDF attachments, preview and extraction.
- [x] Attachment limits: eight files, 10 MB each, 30 MB total, bounded extracted text.
- [x] Local prompt library with search, favorites, variables, editing and deletion.
- [x] Create Prompt with editable context, numbered image previews, refinement, undo and insertion into the draft.
- [ ] Cursor-position context and gesture annotation: point, circle trails, underline and retained marks.
- [ ] Explicit pinned context across follow-ups, with clear removal and freshness semantics.
- [ ] Complete drag/paste attachment behavior at the notch and context drag-out.
- [ ] Create Prompt voice invocation, annotation editing and exported prompt/image bundles.
- [ ] Changed instructions for running jobs, editable queued follow-ups and coherent interruption handling. Do not confuse cancellation with conversational barge-in.
- [x] Public web search results with URLs and bounded HTTPS page reads.
- [ ] Reliable extraction for JS-heavy pages through the approved browser path where needed.
- [ ] Image/YouTube previews, weather, maps/nearby places, stocks/charts and other structured answers.
- [x] Open apps, URLs and configured-folder files.
- [ ] Complete explicit browser/profile targeting. Preserve Ego as the browser automation choice.
- [x] Typed tool catalog, schema validation, bounded tool/result loop and editable consequential-action review.
- [ ] General persistent per-tool confirmation settings and resumable approval cards, beyond current task-local CUA consent.
- [ ] Broader multi-app workflow verification: research -> draft -> review -> action -> follow-up. A successful tool call is not automatically successful delivery.

## 6. Computer use, jobs and announcements

- [x] `CodexComputerUse` launches a real native Codex App Server and discovers `cua_repl.js`.
- [x] It strips inherited embedding-chat CODEX transport identity, keeps the user's proper login environment, validates model/reasoning and starts an ephemeral read-only turn.
- [x] Native apps use granular CUA tools. Browser work receives the installed Ego skill and explicit Ego-only instructions.
- [x] Visible inline permissions above the composer, task identification, serialized requests and one-task reuse of low-risk consent.
- [x] Cancellation, process-exit handling, RPC timeout, tool-call limits and five-minute execution bound.
- [x] `ComputerTaskManager` snapshots request/context/model/provider/reasoning/source chat and owns the queue independently of the recorder.
- [x] Computer jobs serialize the shared desktop. Coding has its own two-worker queue with folder overlap protection.
- [x] Per-job progress/cancel/results; cancellation of dictation no longer cancels background computer work.
- [x] Results append to the originating saved chat; completion preview appears in main chat and notch.
- [x] Completion announcement waits for idle voice/foreground state, honors spoken replies, otherwise plays a sound.
- [ ] Verify completion delivery with different current chats, deleted/archived source chats, history disabled, multiple completions, failed tasks and an active dictation recovery.
- [ ] Verify completion audio, mute/read-aloud preferences, TTS failure and multiple queued announcements. Avoid notification spam or speaking over the user.
- [ ] Persist computer-job records/interrupted states. Current computer queue/notice records are session-only; saved chat results persist. Do not blindly replay interrupted UI actions.
- [ ] Improve shared-desktop focus coordination if live tests show interference with dictation. Do not falsely label UI control as isolated background computation.
- [ ] Expose pending consent reliably if it arrived during recording and could not bring the window forward.
- [ ] Audit browser restriction enforcement. Current Ego-only behavior relies on agent instructions, not a hard capability firewall.
- [ ] Respect the installed CUA plugin's app restrictions, including ChatGPT itself. Do not bypass them or promise arbitrary-app success.
- [ ] OpenRouter and the isolated ChatGPT profile do not currently execute native computer-use turns. Clearly explain the local Codex requirement; do not silently switch accounts.
- [ ] No independent Mac computer-use backend is requested now. This is a deliberate dependency choice, not a parity blocker to 'solve' by rewriting the runtime.

## 7. Dedicated Mac integration checklist

Generic browser/computer use or a user-supplied MCP server is not the same as a built-in tested connector. Do not mark these complete merely because an LLM might navigate the website.

### Existing native adapters

- [x] iMessage: recent conversations, conversation reading, text search, unread messages and reviewed send to exact phone/email.
- [ ] iMessage: richer attributed bodies/attachments, schema compatibility and live send/delivery verification. History needs Full Disk Access; sending needs sign-in and Automation permission.
- [x] Apple Mail: bounded recent Inbox search/read, draft, reviewed single-recipient send and reply draft.
- [ ] Apple Mail: explicit unread parity, full mailbox/content search, mailbox moves and complete reply behavior. Current search is limited to the latest 200 Inbox messages.
- [x] Reminders: lists, search, create, complete/reopen and delete.
- [ ] Reminders: live EventKit verification and advanced recurrence/editor coverage if required. Core listed actions already exist.
- [x] Finder/file tools: configured-folder listing, filename search, reads/info/recent/open, create file/folder, copy, move/rename, append and Trash.
- [ ] Finder: save attached files through a reviewed destination and broader user-authorized locations. Retain symlink/path/size boundaries; do not remove them for convenience.
- [x] Notes: bounded title search, plain-text read/create/append.
- [ ] Notes: folders, comprehensive note listing/search and rich content behavior.
- [x] Apple Calendar: calendars, search/schedule, available intervals and create/update/delete.
- [ ] Apple Calendar: disposable-record testing, all-day/timezone edge cases and recurring-event semantics. Availability is for accessible calendars, not arbitrary attendee availability. Creation does not send invitations.
- [x] Spotify: current playback/status, play/pause, next/previous and volume.
- [ ] Spotify: content search/play selection, shuffle/repeat/seek, queue, library/playlists and remote-device playback.
- [x] Apple Music: current playback/status, play/pause, next/previous and volume.
- [ ] Apple Music: search, queue, favorites, library/playlists and live rich controls.

### Missing dedicated service integrations

Choose direct authenticated APIs or explicitly supported MCP connectors based on the service and the owner's credentials. Keep connection setup honest and do not invent test credentials.

- [ ] Slack: send/schedule messages, read/search conversations, find channels/people, open DM, react, reminders and upload files.
- [ ] Gmail: send/reply/read/search, labels, Trash/permanent deletion and contacts lookup.
- [ ] Google Calendar: calendars, schedule, availability, timed/all-day creation, update and delete. Existing EventKit access to a connected Google calendar is not a dedicated Google connector.
- [ ] Google Maps: documented Open in Maps action. Rich maps/nearby search are additional result/tool work.
- [ ] Outlook: send/reply/draft/read/search/move email; calendar create/update/delete/schedule; create/find contacts.
- [ ] Google Drive: find/create folders/files, upload/download/edit/move/copy/share/delete.
- [ ] Google Sheets: create/read, update cells/rows, add/remove sheets and format cells.
- [ ] Google Docs: create/read/edit documents.
- [ ] Linear: create/update/delete/find issues, comments, labels, attachments, teams/people, projects/states and cycles.
- [ ] Jira: create/edit/delete/find issues, comments, transitions, assignees, attachments, projects/people and boards/sprints.
- [ ] Notion: create/update/read/search pages, append content, query databases/add rows, comments, uploads and people.
- [ ] Obsidian: explicit selected-vault search/read/create/append. General folder tools are not a dedicated vault adapter.
- [ ] Canvas: courses, assignments, grades/submissions, assignment submission, due work, calendar, materials, discussions, inbox and profile.
- [ ] X: post/like/repost, timeline/search, followers/following, send/read DMs and profiles.
- [ ] Microsoft Teams: first verify scope with the owner if prioritized. VoiceOS's Teams claim was not backed by an App Store listing in the recorded research.
- [ ] Custom CRM/Stripe/food-delivery examples are extensibility demonstrations, not verified bundled VoiceOS connectors. Do not turn every marketing example into a mandatory integration.

### Coding integrations

- [x] Codex and Claude executable discovery and explicit integration enablement.
- [x] Review request, engine, folder, available model/reasoning and attachment support before execution.
- [x] Persisted jobs, progress/results/errors, cancellation and recorded-session continuation.
- [x] Two-worker queue with overlapping directories serialized, interrupted-state restore and source-chat result delivery.
- [x] Separate Coding tasks subpage. Integration settings remain under Integrations; job history must not be duplicated in Activity.
- [ ] Official Claude policy/billing verification described in section 2, and equivalent honesty about Codex account limits/authentication.
- [ ] External-session discovery/import, full interactive answers/permissions and voice response to session questions.
- [ ] Parallel-run grouping and combined results, editable queued follow-ups and complete attachment parity.
- [ ] Actual CLI-version compatibility, denied permissions, cancellation of child processes and session resumption tests in disposable projects.
- [ ] Diff review/editor is not implemented. Decide a focused workflow before adding a full IDE to this product.

## 8. Integration platform checklist

- [x] Local stdio/remote HTTP MCP connections, discovery, enable/disable, schemas, reviewed execution and saved credentials in Keychain.
- [ ] Managed OAuth login/refresh/revocation, resources/prompts browsing, elicitation UI and sampling support where applicable.
- [ ] Real-server reconnection, authorization failure and capability compatibility tests beyond fixtures.
- [x] Validated local CLI manifests, direct executable invocation, bounded output/time and explicit enablement.
- [x] Imported local skills with enable/disable and context inclusion.
- [ ] Skill/package supporting resources, versioning, updates and shareable distribution. Do not automatically execute imported scripts as a side effect of reading instructions.
- [ ] AI Integration Studio: plan from description/screenshots, generate code and cards, install draft, conversational refinement.
- [ ] Studio preview/debugging: real turns, tool-card preview, action tests, logs, runtime repair, parallel builds and persisted drafts.
- [ ] Full versioned manifest identity/branding/runtime/setup/permission contract and reload/remove behavior.
- [ ] Rich native result/editable confirmation cards, sandboxed HTML widgets and Widget Kit. Host retains approval control.
- [ ] General synchronous/background integration-tool lifecycle, actionable notifications and durable completion receipts.
- [x] Basic hardcoded quick intents for some commands.
- [ ] Extensible fast intent routing with localized examples, fixed args, typed slots, refreshed enum values and vocabulary hints. Preserve normal validation/approval.
- [x] Explicit app-scoped dictation hooks and enablement.
- [ ] Transcript hooks to add/rewrite/block/handle agent input, tool argument/result hooks, approval hooks and completion receipts.
- [ ] Independently revocable transcript/hook permissions; tool hooks limited to their own integration's tools.
- [ ] Developer-facing manifest verification, MCP tests, intent dry-runs, connection logs and live-test workflows.
- [ ] Hosted runtimes and managed brokered OAuth were reserved/unclear in VoiceOS research. Do not build a hosted service merely to match an unshipped claim.

## 9. Interface, history, memory and privacy checklist

- [x] Global top notch for resting/listening/progress/results/recovery and agent composer.
- [x] Accepted notch shape, pure-black rest state and body-relative gradual glass fade.
- [x] Expand/collapse, source-app icon, explicit mode and result playback controls.
- [ ] Verify Space transitions, fullscreen, short errors, large results, Reduce Motion and Reduce Transparency. Avoid changing the accepted shape while fixing state bugs.
- [ ] VoiceOS's side notch is not implemented. Treat it as a possible design choice, not automatic permission to add another floating UI; owner wants low distraction.
- [ ] Complete appearance/material/layout preferences only if useful within the owner's chosen notch design. An always-visible floating bar was specifically rejected as distracting.
- [ ] Structured maps, thumbnails, charts, statistics, lists, countdowns and live media widgets.
- [ ] Draft-specific insert actions, rich links/attachments and file drag-out/Open With.
- [x] Chat pin/archive/delete and reopening; dictation search/copy/delete/clear/export.
- [x] Dictation totals, words, recorded time and estimated time saved; local maximum 500 entries.
- [ ] Speaking-speed insights and configurable session-reset timing.
- [ ] Percentile comparisons require a legitimate dataset; do not fabricate benchmarks. A shareable statistics card is optional personal-product polish.
- [x] Explicit facts, completed-request episodes, authored procedures, corrections, search/edit/delete and bounded recall.
- [ ] Lockable core preferences, imported knowledge and improved retrieval. Automatic personal/procedural learning needs explicit design and controls.
- [x] History opt-out stops new episode recording/recall while preserving existing entries; recording recovery is separately opt-in.
- [ ] Audit all stores and document exactly what privacy switches control. Job/schedule/integration metadata is not automatically erased by disabling conversation history.
- [ ] Unified private-session mode, clear retention/delete behavior and provider disclosure.
- [x] Basic setup, permission guidance/recovery and launch-at-login.
- [ ] Guided practice/tutorials, support-with-attachments and a consistent update/release-notes path.
- [ ] Shared dictionaries, cloud continuity, team administration and billing are not current deliverables.

## 10. Source map and verified behavior

Workspace: `/Users/aveek/Downloads/Projects/Speek`
Git repository: `/Users/aveek/Downloads/Projects/Speek/app`
Installed application: `/Applications/Speek.app`

Key files:

- `Speek/Assistant/AssistantController.swift`: recorder, foreground state, routing, task handoff and completion notices.
- `Speek/Actions/CodexComputerUse.swift`: app-server transport, native CUA turn, permissions and cancellation.
- `Speek/Actions/ComputerTaskManager.swift`: independent serial desktop queue.
- `Speek/Actions/CodingTaskManager.swift`: coding CLI execution, persistence and project-aware queue.
- `Speek/Assistant/ComputerUseApprovalView.swift`: consent and computer-job UI.
- `Speek/Assistant/BackgroundTaskNoticeView.swift`: completion preview and source navigation.
- `Speek/Assistant/SpeekMainShell.swift`: main navigation and TaskPage enum: chat/history/activity/coding.
- `Speek/Assistant/ActivityCenterView.swift`: non-coding Jobs and Schedules.
- `Speek/Assistant/CodingTaskHistoryView.swift`: coding history/progress/results/continuation.
- `Speek/Assistant/DictationHistoryView.swift`: embedded dictation history subpage.
- `Speek/Assistant/AssistantSurface.swift`: notch materials, layout and voice states.
- `Speek/Runtime/`: runtime tools, research, scheduling and background agent execution.
- `Speek/Integrations/`: MCP and local plugin/hook infrastructure.
- `Speek/Actions/NativeOrganizerTools.swift`, `NativeAppTools.swift`: native integrations.
- `scripts/checks/` and `SpeekTests/`: implementation checks.

Observed live:

- Standalone Codex app-server discovered native CUA without borrowing this development chat's transport identity.
- Installed Speek with GPT-6 Sol controlled Calculator buttons for 17 x 23. Independent AX inspection confirmed 391.
- A later asynchronous Calculator job produced 9 x 7 = 63. Another foreground request was accepted and answered while it waited for permission; the mic stayed enabled.
- Inline task approval was visibly present.
- A returned chat result reported successful LinkedIn company-page navigation. That is useful evidence, but less rigorous than independent final-page inspection; do not generalize it into complete browser coverage.
- Dictation history, Activity and Coding tasks were observed as main-window subpages with retained sidebar and correct selected states. Activity had no Coding tab; Coding had its own empty state.
- Multiple builds were compiled, signed and installed. Live completion audio and simultaneous real dictation during mouse/keyboard automation were not verified.

Source-helper checks passed for computer JSONL framing/errors/cancel/process exit, routine task consent reuse, sensitive consent isolation/reset, independent queue execution/cancellation/source identity, and coding queue/persistence/session-folder behavior.

## 11. Engineering and delivery rules

- [ ] Inspect `git status` and local instructions before edits. There are many existing modified and untracked files from this project. Do not discard them, reset the repository, or create a wholesale unrelated commit.
- [ ] Use ASCII in generated code, comments, documentation and communication. Never write U+2014.
- [ ] Keep stable signing identity `Speek Dev Signing` and canonical `/Applications/Speek.app`. Do not change bundle identity, reset TCC or install an ad-hoc signed copy as a routine fix.
- [ ] Check for recording and running background jobs before replacing the app. Repeated restarts can destroy session-only computer jobs and notices. Defer restart while work is active.
- [ ] Use a staged verified bundle swap and keep a recoverable previous build. Merely compiling does not update the running app.
- [ ] Do not expose API keys, copy authentication caches or borrow credentials from unrelated tools. Missing user credentials are a valid handoff requirement.
- [ ] Prefer capability checks and explicit errors to invented success/fallback. Preserve selected models and no silent account switch.
- [ ] Keep browser QA in Ego. Use native UI tools for native-app QA. Do not build a hidden second browser automation route.
- [ ] Perform real action/result verification. A screenshot, model statement, passing build or mocked tool call is not proof of actual external completion.
- [ ] Do not send email/messages, create real appointments, publish, purchase or delete real user data as a test without specific authorization. Use disposable fixtures and explicit test destinations.
- [ ] Use current official provider documentation for model IDs, capabilities and billing/policy decisions. The research map is a dated baseline, not a current policy authority.
- [ ] Update feature status and UI registry after meaningful changes, removing contradictions rather than only appending another conflicting section.

Build used successfully:

```sh
xcodebuild -project Speek.xcodeproj -scheme Speek -configuration Debug \
  -derivedDataPath .feature-build -xcconfig LocalBuild.xcconfig \
  CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO build
```

That build still requires stable signing and installation. `scripts/dev-build.sh` is another existing path; inspect its install/restart behavior before running it during active work.

Relevant checks:

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
swiftc -parse-as-library Speek/Actions/ComputerTaskManager.swift \
  scripts/checks/ComputerTaskChecks.swift -o /tmp/speek-computer-task-checks
/tmp/speek-computer-task-checks
```

Do not rerun every check for a trivial visual edit. Choose checks for the changed behavior and remaining risk.

## 12. Recommended execution order and acceptance

This order is an engineering recommendation, not a new owner-approved business requirement.

1. [ ] Stabilize the actual promise: real voice -> app/browser action -> verified result -> main-chat delivery -> non-disruptive announcement. Cover permission waits, errors, cancellation, concurrent dictation and restart recovery first.
2. [ ] Resolve coding policy/auth assumptions and verify real CLI behavior. Preserve the separate background execution model and single coding-history destination.
3. [ ] Finish high-value dictation quality: corrections, contextual vocabulary, language preferences, capture/media behavior and recovery.
4. [ ] Extend the integrations the owner actually uses, with honest setup and testing. Accounts/credentials can be supplied later, but connector logic and review/error states must be real.
5. [ ] Finish rich action/draft/result cards and missing prompt/context interactions using existing design patterns.
6. [ ] Build advanced hooks, intent routing and developer tooling only after the core paths are dependable. Do not prioritize a marketplace or integration generator over basic app control.

For each completed feature:

- [ ] State what changed and which gap it closes.
- [ ] Verify the real source path and meaningful failure/cancellation behavior.
- [ ] Verify visible empty/loading/populated/error states and narrow/wide layout where affected.
- [ ] Test source-chat delivery without overwriting newer work or interrupting dictation.
- [ ] Record what was live-tested versus fixture-tested.
- [ ] List exact remaining user setup, credentials or permission needs.
- [ ] Mark the checklist only to the level the evidence supports. Do not call a wiring-only feature production-ready.
