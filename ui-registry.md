# UI registry

This registry records the new Workspace. Other Speek pages still use `SpeekDesign.swift` and have not been audited here.

### Action workspace

File: `Speek/UI/Pages/ActionWorkspacePage.swift`
Last updated: 2026-09-25

| Property | SwiftUI value |
| --- | --- |
| Main background | `Color(nsColor: .windowBackgroundColor)` |
| Task rail background | `Color.primary.opacity(0.025)` |
| Message and example background | `Color(nsColor: .controlBackgroundColor)` |
| Review background | Blue accent at 0.07 opacity |
| Review border | Blue accent at 0.23 opacity, 1 point |
| Corner radius | 18 for empty state, 16 for review card, 14 for messages, 11 for examples and task rows |
| Heading | System rounded, 30 points, semibold; dynamic white in dark mode |
| Body | System, 13 points; secondary system color for supporting text |
| Caption | System, 10 to 11 points; tertiary system color for low-priority help |
| Accent | RGB 0.17, 0.34, 0.70, used for buttons, selected task, and review state |
| Spacing | 27 points page inset, 22 points between sections, 15 to 22 points inside cards |
| Shadow | None |

Pattern notes: The task rail is quiet and the request composer stays visible. The blue accent marks actions rather than decoration. Use system semantic backgrounds and text colors so the desk reads in both appearances. Keep action previews separate from conversation messages, and show a plain-language execution boundary next to Codex tasks.

### Task context sheet

File: `Speek/UI/Pages/ActionWorkspacePage.swift`
Last updated: 2026-09-25

| Property | SwiftUI value |
| --- | --- |
| Background | Native sheet background |
| Editor border | Primary text at 0.12 opacity, 9 point radius |
| Title | System, 22 points, semibold |
| Body | System, 13 points, secondary color |
| Help | System, 11 points, secondary color |
| Spacing | 14 points between elements, 25 point inset |
| Accent | Native prominent Save button |
| Shadow | None |

Pattern notes: Explain what context is stored and sent before the user saves it. Keep the notes editable and explicitly scoped to one task.

### Connections

File: `Speek/UI/Pages/ActionConnectionsView.swift`
Last updated: 2026-09-26

Shared between onboarding and the Connections sheet. Use 13 point semibold names, 11 point secondary descriptions and status, 14 point spacing, native dividers, and glass capsule buttons. Only OpenRouter shows an API key input. Keep voice selection separate from the task connection. The composer contains the per-conversation connection picker; switching clears pending proposals and Codex session continuity.

### Action buttons

Files: `Speek/UI/Shell/SpeekOnboardingView.swift`, `Speek/UI/Pages/ActionWorkspacePage.swift`
Last updated: 2026-09-26

| Property | SwiftUI value |
| --- | --- |
| Primary action | `.buttonStyle(.glassProminent)` |
| Secondary action | `.buttonStyle(.glass)` |
| Text button shape | `.buttonBorderShape(.capsule)` |
| Composer icon shape | `.buttonBorderShape(.circle)` |
| Primary control size | `.controlSize(.large)` |
| Hover, focus, pressed | Native system behavior |

Pattern notes: Set the border shape explicitly. Do not replace native glass button backgrounds with painted circles or use bordered styles for Workspace actions.

### Accessibility setup helper

File: `Speek/UI/Shell/PermissionsGuideView.swift`
Last updated: 2026-09-26

Shared between onboarding and the floating permissions guide. Use native glass capsule buttons, a 12 point rounded app drag tile with quaternary fill, 13 point action text, and secondary captions. Show the installation action only outside Applications. The draggable tile carries the running app's file URL. Permission state refreshes automatically; macOS owns the final switch.

### Ambient assistant

Files: `Speek/Assistant/AssistantSurface.swift`, `AssistantSettingsView.swift`
Last updated: 2026-09-26

The product lives in a non-activating floating panel across Spaces. The collapsed control is a quiet native-material capsule with waveform and expand actions. Expanded requests use a single 24 point rounded material surface, an 18 point inset, 12 point spacing, 19 point empty-state text, 14 point response text, and 10 to 12 point controls. No card grid, colored sidebar, chat bubbles, or model library. Status, removable context, current response, and composer form one vertical reading order. Native glass capsule buttons are reserved for task approval and settings actions.

(Superseded by "Settings ownership" below.)

### Main application shell

File: `Speek/Assistant/SpeekMainShell.swift`
Last updated: 2026-09-26

The main screen follows the user's Codex reference: a 56 point icon rail, a 242 point task sidebar, and a quiet content pane. Neutral dark surfaces use white levels 0.17, 0.125, and 0.092. The composer uses 0.19 with a 20 point radius. SF system type: 17 point sidebar title, 12 point task rows, 14 point content, 11 point supporting controls. Content and composer share a 720 point maximum width. Hover feedback uses low-opacity white; selected rows do not use a bright accent. Keep other screens inside the same shell. This main-screen direction supersedes earlier dashboard patterns; the floating assistant remains a separate shortcut interaction.

### Shell refinements

Last updated: 2026-09-26

Task sidebar width is persisted from 180 to 380 points with a single physical-pixel separator, an invisible eight-point drag target, and an accessible adjustment action. The divider occupies no layout width. Its hairline increases opacity on hover and throughout a drag; the hit target stays invisible. Resizing uses global pointer coordinates to avoid feedback as the sidebar moves. The icon rail has no profile or account badge. The top bar shows real request/recording/background-task status. Integrations is a separate rail destination from model Connections. Integration rows use restrained disclosure groups with honest Available or Planned labels. Memory separates Facts, Vocabulary, and History; vocabulary drafts are saved but are not represented as active speech tuning. Secondary screens share a 740 point content width, 32 point inset, 25 point medium heading, and 12 to 13 point body text.

### Continuous window material

The main window uses full-size content with a transparent native title bar and one behind-window NSVisualEffectView sidebar material spanning the header, icon rail, and outer frame. The task list darkens this shared material with a translucent black tint. A single rounded inset contains the task list and opaque content canvas. Header controls sit directly on the shared material; empty header space drags the window.

### Compact native title bar

The shell uses an empty native unified-compact toolbar for system-managed traffic-light alignment and title-bar height. No task title, readiness indicator, or task menu appears in the title bar. Content respects the native top safe area; only the shared frosted background extends beneath the transparent title bar. This replaces the custom 48-point header and drag region.

### White icon treatment

Shell icons are white, including secondary actions and task rows. Navigation and task selection use outline symbols when inactive and filled variants when active. Connections uses powerplug and Settings uses gearshape so both have matching outline and fill variants. Text retains its existing secondary hierarchy. The send button uses a white glyph over a dark translucent circle.

Outline navigation icons use SF Symbols light weight at 18 points. Active filled variants retain regular weight. Search and unselected task glyphs also use light outlines. Icon color and layout are unchanged.

Navigation symbols: Tasks uses house / house.fill; Connections uses link.circle / link.circle.fill. The 38-point Settings button sits in the 56-point rail with 9-point side insets and a matching 9-point total bottom inset (3 inside the rail plus 6 from the shell).

User-selected navigation symbols, in order: tray, memories, poweroutlet.type.f, personalhotspot. Settings remains gearshape at the bottom. Use native fill variants for tray, poweroutlet.type.f, and gearshape when selected. Memories and personalhotspot have no fill variant and retain their symbol with the existing selected background. This supersedes earlier icon choices.

Latest icon update: position 2 uses microbe; position 4 uses puzzlepiece.extension with puzzlepiece.extension.fill when selected. Positions 1 and 3 are unchanged.

Outer sidebar icons always use filled SF Symbols at regular weight, including microbe.fill and gearshape.fill. Selection is indicated only by the existing background. This supersedes outline/filled selection rules for the outer sidebar.

### Contextual voice pill

Always-visible 224 by 44 point non-activating capsule, native dark glass. A 24-point current-app icon sits left, two lines show voice mode and app name, and a 28-point microphone/stop target sits right. White glyphs, 11-point medium state, 9-point supporting app name. Three tiny bars show real microphone levels only while recording. App and mode freeze for the active recording. The mode menu exposes Automatic, Dictation, and Agent plus typed requests. Dictation remains collapsed through recording and transcription; failures expand with a recoverable transcript and Copy action. Clicking the recording control must never take keyboard focus.

### Restored recorder glass

The contextual pill reuses MiniRecorderPill's clear interactive glass with black tint 0.16. No custom stroke and no NSPanel shadow. A 212 by 40 point capsule holds 28-point end targets with equal 6-point insets on all sides. Its transparent host adds 18 points for the soft shadow and spring overshoot. Reveal uses the original response 0.55, damping 0.52 spring; Reduce Motion disables it.

### Floating panel layout and controls

The pill's HStack expands before padding. Its native menu gets flexible width on the Menu itself, not just its SwiftUI label, so AppKit cannot center a narrow intrinsic row inside the wider capsule. End slots are 28 points with equal 6-point insets. The mode is a single line; app identity remains visible through the icon and tooltip.

The expanded panel uses 12-point content insets and gaps, a quiet 32-point header, a bounded response area, and one rounded composer. All icon actions have explicit 32 by 32 rectangular hit regions with hover feedback. Context selection, connection switching, voice, send, and playback live in the composer toolbar; conversation management stays in the header menu. Native menu indicators are hidden. Response and draft lengths, context, recoverable dictation, and task approval determine panel height. The same stable certificate signs installed builds.

Verified the running compact and expanded layouts with Computer Use; the collapse action returns to the pill. A coordinate-based edge-click check was unavailable from the computer-use server, so only the accessibility action was verified interactively.

## Main composer model selection
- Context uses a 32-point plain plus button and a popover, with no native menu indicator.
- A single compact model button opens a connection selector and searchable model list.
- Automatic means the chosen connection's default model, never account failover.
- Model catalogs are account-specific for Codex and fetched from OpenRouter for structured-output models.
- Persist the selected model per task and pass it to both routing and file execution.
- Disconnected providers lead to Connections. OpenRouter file execution explicitly requires a Codex connection.

## Connection feedback
- Show a checkmark beside a connected account and label its action Reconnect.
- Refresh on return from browser authentication, as well as after login completes.
- Automatic visual context is named explicitly in Settings; region attachments remain pinned through voice start.

## Connections page: progressive disclosure
- Center settings content at a maximum width of 680 points; maintain a single column.
- System typography: 25 semibold page title, 13 section/row titles, 11-12 supporting text.
- Use two grouped surfaces for Accounts and Defaults, separated by 28 points.
- Surface radius 20; account detail radius 12 with an 8-point inset. Row padding 16, icon slot 28, icon-to-label gap 12.
- Keep connection status visible; reveal sign-in and credential management by expanding the full row.
- Native glass capsule buttons are reserved for actions, not every settings row.
- OpenRouter defaults use a searchable live catalog, filtered for image input and structured output.
- Voice expands separately; advanced audio endpoint IDs remain behind a second disclosure.
- Adaptive label/control rows stack vertically when horizontal space is insufficient.
- Disclosure animation respects Reduce Motion. White symbols remain consistent with the shell.

## Audio selection
- Dictation model, speech model, and voice use searchable popovers populated from OpenRouter's live modality catalogs.
- Voice names are formatted for reading; identifiers remain internal.
- Speech models with no published voice list are excluded until a dedicated cloning/default-voice flow exists.
- Selecting a speech model chooses a supported voice atomically. Preview uses the selected pair without changing other preferences.
- Default agent model is GPT-6 Luna; default OpenRouter audio is GPT Transcribe and MAI Voice 2 Flash. Legacy defaults migrate once; other explicit choices are preserved.

## Selection indicator standard
- All custom model and voice picker selections use `checkmark.circle.fill`, 13-point, white. Never use a bare checkmark for these selection states.

## Picker consistency and reasoning
- Settings model and voice triggers use quiet rectangular surfaces: radius 6, height 26, white fill at 8 percent. Searchable popovers remain; glass capsules are for actions only.
- Composer model control shows a readable model name, connection label, provider symbol, and reasoning level. Hover/open states use a subtle capsule highlight.
- Provider tabs use rounded neutral selection surfaces, replacing the blue segmented control.
- Reasoning choices come from provider model metadata and persist per task. Requests and file execution receive the chosen effort; changing model or connection resets it to the model default.

## Composer chip refinement
- Chip content is the readable model name followed by its provider logo only; no sparkle, provider text, reasoning text, or chevron.
- Reasoning remains inside the selector. Automatic shares the same list container and leading inset as every model row.
- Disconnected provider tabs use gray text with a leading lock. The selector header has no Connections link.
- Codex vector asset sourced from lobehub/lobe-icons (packages/static-svg/icons/codex.svg).

## Verified provider marks
- Use ActionConnection.logoAsset everywhere a connection is identified visually.
- Codex, ChatGPT, and OpenRouter have distinct sourced SVGs. See docs/PROVIDER_LOGOS.md for provenance.
- Keep their original geometry; render white via template assets. No generic symbol substitutions.

## Task sidebar management
- New task, search, and chat rows share a 9-point horizontal inset.
- New task has the rail's 9-percent white active background with an 8-point corner radius.
- Chat rows expose actions through a trailing ellipsis on hover only and a context menu.
- Pinned chats sort above recent chats. An archive toggle beside the section label exposes archived chats and restoration.
- Delete confirms before removing history. Active recording/execution disables archive/delete.

- Hover-only chat menus are conditionally inserted, never hidden with opacity while reserving width. Idle titles use the row width with 11-point leading/trailing content insets.

## Memory groups
- Memory matches Connections: centered 680-point content, 24-point outer insets, 25-point semibold heading, and 28-point section spacing.
- Disclosure groups use 20-point corners, 16-point row insets, a 28-point icon slot, and inset dividers. Facts, Vocabulary, and History remain independently expandable.
- Add forms appear inside the relevant group with 12-point nested corners and padding. Save and Cancel align to the trailing edge; long content wraps and fields stack at every width.
- Saved rows keep a 32-point removal hit area and accessible labels. Vocabulary explicitly states its current dictation limitation.
- The task sidebar has no static shortcut footer.

## Unified settings backgrounds and integrations
- All non-chat shell pages use the native windowBackgroundColor, matching Connections. The darker canvas belongs to chats only.
- Connections, Memory, and Integrations share settingsSurface for grouped card fill, border, and 20-point corners.
- Integrations uses the same centered 680-point column, heading, spacing, icon slots, and disclosure rows. Available commands show checkmark.circle.fill; unfinished integrations are labeled Planned.
- Detail panels use 12-point corners inside 8-point outer insets. Long descriptions wrap; status labels retain their width.

## Integrations library correction
- Integrations is a plugin and skill library, not an account-settings list. Plugins encompass MCP servers, app CLIs, and internal hooks. Skills hold reusable instructions and resources.
- Use neutral Plugins/Skills pill tabs and an adaptive card grid with 16-point gaps, 20-point card insets/corners, and 44-point icon tiles.
- Preserve the Connections background color. Cards disclose details; unfinished installation and import are explicitly marked unavailable, never shown as installed.
- This replaces the earlier grouped Integrations disclosure-row design.

## Memory library tabs (2026-09-27)
- Layout follows content shape. Facts, Episodic, and Vocabulary are grouped lists (statements, dated events, and word pairs are scanned). Procedural uses the Integrations tile grid (titled documents, like skills).
- Episodic groups events under day headers (Today, Yesterday, weekday and date), newest first; tap a row to expand it. Vocabulary rows read "heard as -> write as", sorted by term.
- One header row on every tab, fixed 32-point height: title and info leading, `SpeekSearchField` and the add action trailing. Never place a full-width search bar between the header and content.
- Row edit and delete controls appear on hover (`HoverRowActions`). Add and edit open a 460-point sheet; never insert inline editors that reflow the page.
- The history-saving switch lives only in Settings > Privacy; Episodic shows `HistoryPausedNotice` when it is off.
- Tabs use the shared `PillTabs` component (also Integrations and Settings).

## Primary creation actions (user design rule)
- Place the primary Add/Create action beside its section heading, above the content grid. Never leave it floating at the bottom or across empty space away from its context.
- Use a compact labeled button with a plus icon, 13-point medium text, regular control size, and modest extra padding (3 points horizontal, 2 vertical). Do not combine large native control sizing with a forced content height: their padding compounds into an oversized pill. Align its center with the heading; put supporting copy below.
- Apply this consistently to every supported memory creation action and future library screens. Do not add fake creation actions for unimplemented features.
- Keep actions near their associated content at narrow widths, moving them below the heading when necessary.


## Flat action buttons (current user preference)
- Use SpeekActionButtonStyle for Add, Save, Cancel, Done, Preview, Connect, permission, and similar actions throughout the main pages and assistant.
- Flat neutral fill, 8-point corners, 13-point medium text, and 12-by-7-point padding. No glass sheen, capsule border, or shadow for these actions.
- Hover and pressed states change the fill; disabled actions are subdued. Header placement stays unchanged.
- This supersedes earlier recommendations for glass capsule action buttons. Glass remains appropriate for the window and floating assistant material, not ordinary page actions.

## Settings ownership (user rule, 2026-09-26)
- One setting, one home. Never show the same control on two screens; elsewhere, show a status line with a link to its home.
- Each setting has one home. Models & Voice: accounts, default provider/model/reasoning for new chats, voice connection, dictation and speech models, voice, spoken replies and speaking speed. Settings: General (speak shortcut, double-tap hands-free, screen context, launch at login), Dictation (microphone, recognition language, vocabulary hints, writing mode and style, Edit Mode), Privacy (save history, recording recovery), Permissions (Microphone, Accessibility, Screen Recording). Memory: Facts, Episodic, Procedural, Vocabulary (names, terms, corrections, spoken shortcuts). Integrations: Plugins, Native apps (Calendar, Reminders, Mail, Notes, music, Messages, Files working folder), Local tools (Codex and Claude Code, CLI manifests, hooks), Skills. App-specific macOS access is requested from its integration card.

## General settings page
- Use the Connections layout for preferences: centered 680-point column, 25-point heading, 28-point section gaps, and shared settingsSurface groups.
- Settings uses the same neutral pill tabs as Integrations: General, Dictation, Privacy, Permissions.
- Every settings row uses `SettingsRow` / `SettingsSection` (`Speek/Assistant/SettingsRow.swift`): 16-point row padding, 19-point white icon in a 28x32 slot, 13-point medium title leading, control trailing on the same line. Never stack a switch or menu under its label. Do not shrink padding, icons, or type when removing text; density matches Integrations and Models & Voice.
- No explanatory paragraphs under rows or sections. Explanations go in `InfoButton` (tooltip on hover, popover on click) and only where the option is not self-explanatory. The secondary line under a title is reserved for live state: a path, a count, an error, a paused state.
- Permissions retain live state and use checkmark.circle.fill with Allowed, or the shared flat Allow action. Redesigning permission rows must not alter grant or refresh logic.
- Version is an About row with the value trailing; license text lives in its info button.

## Sidebar type and native symbol motion
- Chat titles, New task, and task search use 13-point regular text. Recents stays 11-point medium as a secondary heading.
- Sidebar selection uses native SF Symbols Draw On, as specified below. Backgrounds stay still; custom provider SVGs do not receive symbol effects.
- Recording uses native Breathe on microphone/stop symbols and Variable Color on the expanded waveform. Effects stop when recording ends and are disabled under Reduce Motion.

## Models & Voice and new-chat defaults
- Rename the account/defaults destination Models & Voice. Accounts manage authentication; New chats and Voice disclose their own defaults.
- New chats exposes provider, searchable model selection, and supported reasoning levels. Reuse the same rectangular searchable control as voice selectors.
- Every new chat snapshots the saved provider, model, and reasoning. Chat-specific overrides never change defaults; changing defaults never rewrites existing chats.
- Remember model/reasoning per provider; selecting a different default model resets its reasoning to model default. Failed catalog loads preserve the saved choices.


## Content-sized selectors
- Model and voice triggers fit their selected text, padding, and chevron, capped at 250 points for long names. Do not stretch short selections to a uniform width.
- Align selector right edges to the trailing content inset. Narrow stacked rows keep controls right-aligned, never centered or leading-aligned.
- Search popovers retain their independent readable width.

## Sidebar symbol drawing
- Sidebar activation uses Apple's SF Symbols Draw On effect with the symbol's native layer paths. Do not substitute bounce, scale, rotation, or a hand-drawn overlay.
- Keep the filled symbols and button backgrounds stationary. Draw only the activated icon once; do not loop. Reduce Motion disables drawing.

## Notch assistant
- The persistent assistant attaches to the top center of the built-in notched display. Use the actual screen safe-area inset to keep all controls below the camera housing.
- Idle occupies only the notch height, with a 32-point wing on each side. The left wing shows the focused app; the right shows the input mode. Nothing extends below the notch. Clicking opens the assistant; the global hold shortcut starts speech.
- Listening and processing use a 48-point row below the notch with captured app context, input mode, and audio or progress feedback.
- Responses expand downward in the same component, with an opaque black camera cap fading into native Liquid Glass with a scrollable body, Copy, follow-up composer, and Dismiss. Keep pending proposals when collapsed.
- Never move this component by dragging. Re-anchor when displays change. Respect Reduce Motion when resizing.

- Expanded results have one copy action. Recovered dictation takes precedence over the accompanying error message; label it Copy dictation and copy only the transcript.


- The notch panel stays stationary across Spaces using canJoinAllSpaces, fullScreenAuxiliary, stationary, and ignoresCycle, at mainMenu + 3. Disable implicit window show/hide animation. Never add a Space-change timer, opacity toggle, or forced focus change. Reference: https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/components/Notch/BoringNotchWindow.swift . Speech and drafts survive desktop switches.

- All Settings entry points open the Settings route in SpeekMainWindow. Do not register another SwiftUI Settings scene or standalone settings window.

- Global notch placement requires a dedicated WindowServer Space, following Boring Notch's NotchSpaceManager, in addition to panel collection flags. The dynamically resolved private API is isolated in NotchGlobalSpace. Hide it on screen lock and destroy it at termination. Fall back to the AppKit status-bar panel if unavailable.

- Set isFloatingPanel before the notch window level: enabling it resets the level to floating. AssistantPanel overrides constrainFrameRect because its explicit screen-edge frame intentionally occupies the menu-bar strip. Verify WindowServer reports Y = 0 after launch, not the menu-bar height.

- Notch contour uses 4-point upper concave curves and 8-point circular lower corners at rest, following the hardware-oriented Iconfactory Notchmeister reference: https://github.com/chockenberry/Notchmeister/blob/main/Notchmeister/Notchmeister/NotchExtensions.swift . This is a source-informed approximation, not an Apple-published specification. Read actual notch width and height from NSScreen auxiliary areas and safeAreaInsets. Keep idle glyphs 2 points above center.
- Expanded notch uses native Liquid Glass with a black gradient: fully opaque through the camera strip, progressively translucent below. Fade its black cover with the 0.22-second expansion. Idle and listening stay opaque. Reduce Transparency keeps it opaque; Reduce Motion disables the fade.

- Expanded notch controls live in the camera-height wings: status glyph on the left, options and dismiss on the right, with an explicit NSScreen-derived camera exclusion width. Status words belong in accessibility/help, never a separate header row. Use the shared AssistantModelPicker in the notch composer. Measure response and recovered dictation text to size short panels without fixed recovery whitespace.

- Resting notch uses the original 4-point top shoulders and softer 12-point bottom curves. Keep window dimensions and glyph positions fixed. Expanded/active curves retain their existing radii.
- Notch composer places the shared model picker in the trailing control group. Show Copy dictation only when pendingDictation contains text that failed insertion; normal command responses have no copy row or reserved copy-row height.

- Resting and compact active notch backgrounds are opaque sRGB #000000. Remove the glass material from the view hierarchy in these states; covering a live glass layer is insufficient. Glass exists only in the expanded panel, with Reduce Transparency using the same opaque black fallback.

- Keep upper notch shoulders at 4 points in every state. The larger 12-point resting radius applies only to the bottom corners.

- Anchor the expanded notch composer to the bottom with 12-point side and bottom insets from the visible outline. Its 12-point radius is the 24-point outer radius minus the 12-point inset. Empty-body space belongs above the composer, never beneath it.

## Notch interaction states (current)
- Idle left opens the agent composer and shows the current external app. Desktop (Finder without a focused window), Speek itself, and unavailable foreground targets clear stale app data and use the SF symbol siri.gen2 (siri fallback). Idle right starts the displayed voice mode; right-click exposes a mode override.
- Dictation captures its destination once at recording start. Recording/transcription has no composer. Failures open a dedicated transcript/error surface with Copy dictation and dismiss; no agent context, model picker, or speech playback. Recovered dictation remains reachable from the options menu after opening the agent composer.
- Opening the agent composer refreshes unpinned context, including clearing it when unavailable. Context rows explicitly identify attached context. Circled regions remain pinned. The composer microphone explicitly starts an agent request, matching the main app.
- Playback belongs to the visible assistant response, never the composer. It reads that message only and changes to Stop while playing. A new request or error clears stale response playback. The upper-left idle status decoration is replaced with the Siri assistant symbol (or the captured dictation destination in recovery).

- Desktop idle uses the real Finder app icon, including the default when no external app is available. Clear the previous input target and use agent mode. Siri is no longer used as the fallback. The agent header uses Speek's app icon. Models & Voice uses sparkles.rectangle.stack, filled when selected.

- All navigation rail items, including Settings, use the outline symbol when unselected and the filled symbol when selected. Apply the same rule to Tasks, Memory, Models & Voice, and Integrations.

- Resting pill mode indicator: sparkle for agent mode, microphone.circle.fill for dictation. These symbols indicate the mode started by the button and hold shortcut.

- Resting mode icons: waveform for dictation, sparkle for agent. Resting app artwork is 17 points and mode symbol uses 13-point type, a 1-point increase. Keep the 32-point hit areas, vertical offsets, and notch dimensions unchanged.


## Integration requests and activity
- Codex and Claude Code are opt-in integrations under Local tools. Coding history has one sidebar destination, the Coding tasks subpage.
- A user request opens a compact review sheet for the integration, project, request and permissions. Ongoing work and results belong on the Coding tasks subpage.
- Integration switches report enabled state separately from CLI installation. Installation does not imply authenticated or connected.
- New settings use the existing page background, settingsSurface groups, 13-point labels and compact flat action buttons. Controls align right at intrinsic width; descriptions wrap before controls.

## Computer-use permissions

- Keep pending permission requests outside the transcript scroll area, immediately above the composer, so they cannot be hidden below the fold.
- Use the existing compact flat action-button style and a 14-point rounded card. Align actions to the trailing edge.
- One explicit Allow this task covers routine low-risk native Computer Use actions for that task. Do not ask again for every click or screenshot. Sensitive or unknown requests remain separate.
- Preserve the selected model. Do not promote routine tasks to Astra.
- Browser work uses Ego Browser and its installed skill. Do not add an embedded or Codex in-app browser.

## Background computer tasks

- Keep job progress and per-job Cancel controls in the Tasks transcript area.
- Permission cards stay above the composer and identify the requesting job.
- Job completions use a separate result notice in the main chat and notch. Defer notch expansion and announcements until foreground work and dictation finish. Honor the spoken-replies preference; otherwise use a short completion sound.
- Flat compact controls and 14-point rounded cards match the existing action UI.
- Voice-session cancellation and background-job cancellation are separate.

- Memory navigation uses `point.3.connected.trianglepath.dotted` when inactive and `point.3.filled.connected.trianglepath.dotted` when selected.

- The expanded notch glass fade begins below the physical camera strip. Position
  every opacity stop relative to the remaining body height, with strictly ordered
  stops, so short dictation error panels retain a continuous fade.

- Task sidebar destinations use 15-point regular system labels, 15-point icons in an
  18-point column, 10-point icon/text spacing and 10-point vertical padding.
- Activity and schedules, Dictation history, and Coding tasks are distinct chat-area
  subpages. Keep the task sidebar visible and highlight only the selected destination.
  Coding history belongs only in Coding tasks; Activity has Jobs and Schedules tabs.

- Apply the same 15-point sidebar label size to New task, destinations, search and
  recent chats. Section headings use 13 points. Keep regular weight for rows.

## Integrations layout (2026-09-26)
- Rule: what Speek ships is a grouped list; what the user adds is a grid of equal tiles. Components live in `Speek/Assistant/IntegrationComponents.swift`.
- Native apps: single-column grouped list (Communication, Organization, Media, Files) at the full 880-point column. Each row shows the real app icon (`AppIcon`), title, info button, and one trailing switch: on means Speek may use it. Switching on requests macOS access; a spinner replaces the switch while it runs. Denied access shows "Open System Settings" instead of a switch. Never mix Connected labels, Connect buttons, and switches in one list.
- Local tools: Coding assistants as a grouped list (brand marks, switches), then Command-line tools as a tile grid.
- Plugins (MCP) and Skills: tile grid, adaptive 230 to 420 points, fixed 184-point tiles so rows align. Tile: 44-point glyph, 14-point semibold name, two-line subtitle, status bottom-left, primary control bottom-right (switch or Connect/Manage), overflow menu top-right shown on hover. Tapping the tile opens details.
- Empty shelves show one placeholder tile of the same size, not a floating message. The add action stays beside the section header.
