# Speek: ambient assistant

## Product decisions

Speek stays available over the user's current app. The global shortcut starts online recording without opening settings or a workspace. A floating control provides typed requests, recent conversations, screen-region context, task review, and replies. Simple website, search, and installed-app opens execute immediately. File tasks use an explicitly chosen directory and Codex workspace-write sandboxing.

There is one settings window. The old dashboard, offline model library, dictation modes, separate agent panel, and multi-step onboarding are not reachable from the product. The application entry point no longer constructs the legacy transcription engine, local model managers, prewarming, or idle recorder. Legacy source remains for migration and compile compatibility; it is not initialized by the app.

## Context and memory

- Active app, window title, and selected text are captured when the assistant is invoked, before it takes focus. This can be disabled in General.
- Circle context captures the display under the pointer, excludes Speek, and sends the bounding crop of the drawn selection with the next request. Screen Recording permission is requested only when needed.
- Screen images stay in memory, except for a private temporary image used by the Codex CLI and removed after completion.
- Saved conversation text and explicitly remembered facts stay in Application Support. Relevant previous requests and saved facts are included in subsequent requests. This is bounded local retrieval, not a claim of perfect or unlimited recall.
- Full disk access and a third-party memory service are future integrations. Current file changes remain restricted to the selected folder.

## Reference study

Avo: https://github.com/Stu1124/avo
Inspected revision: 8cd34c2f7c04d439941e5c70c3bbfb460e26dec8

Patterns studied: non-activating panel, compact response lifecycle, pre-activation context capture, rolling conversation history, and separation of long tasks from the immediate response. Speek retains its own UI and cloud voice architecture. No Avo source was copied. Avo's local speech, local model configuration, and six-step onboarding are not adopted.

VoiceOS: https://www.voiceos.com
The reference reinforces cursor/screen context, voice-to-action, and minimal interruption of the current app.

## Verification

The ambient build compiles and passes signature verification. Eight quick-intent checks cover exact app opens, explicit memory requests, and rejection of compound or file-URL shortcuts. A live UI test opened Calculator and verified automatic collapse. All four settings sections were inspected. Live microphone and screen-selection verification remain dependent on macOS granting this installed development build access.

## Contextual dictation

The persistent pill polls the frontmost application's macOS Accessibility focus every 300 ms. It reads roles and editability, not field contents. Text fields, editable browser controls, and editors with writable selection use Dictation; other controls use Agent. Password fields block recording. Missing Accessibility access is shown explicitly. Users can override automatic mode for apps with incomplete accessibility support.

Mode and target are captured before recording. Dictation uses the configured online transcription provider and never enters agent routing or conversation history. The existing clipboard insertion path rechecks application and focused element before posting Paste, preserves the clipboard, and does not press Return. A changed target retains the transcript for manual copying. Silence is rejected before transcription. Cancellation waits for audio teardown before accepting another recording.

Verification: app builds; ten focus-policy cases pass in a standalone Swift harness; a live OpenRouter speech/transcription round trip returned the expected sentence. Live microphone-to-external-editor testing still requires the user's OS permissions and spoken input.

## Development signing and Accessibility

Use the existing Speek Dev Signing identity for every installed development build. Ad-hoc signatures have a per-build cdhash designated requirement and invalidate the Accessibility grant on replacement. The installed build now has a certificate-bound designated requirement. The existing macOS Accessibility grant was recognized after restoring this identity, verified in Speek Settings without resetting TCC or changing its toggle. scripts/dev-build.sh fails before installation if stable signing is unavailable or fails. Do not install the raw ad-hoc Xcode product: sign with the persistent identity and verify the signature first.

Voice activation no longer raises a system Accessibility prompt on each attempt. A denied permission produces an in-app explanation; the explicit Allow action owns the system prompt. Never treat a stored preference as proof of OS authorization.

## Permission detection correction

Passive UI refresh now uses CGPreflightScreenCaptureAccess at display time, periodically while Settings is visible, and when Speek becomes active. It never calls ScreenCaptureKit just to check status. CGRequestScreenCaptureAccess is reserved for the explicit Allow action. Real user-initiated capture calls ScreenCaptureKit; userDeclined is classified as authorization denial while other errors remain capture failures. No permission result is fabricated from an enabled-looking toggle or a saved preference.

The installed build returned SCStreamErrorDomain userDeclined (-3801) while System Settings displayed an enabled Speek entry. Stable certificate signing is verified, but that older Screen Recording grant still needs OS-level reauthorization. Do not claim screen capture works until reauthorization and a successful capture are verified.

The shortcut now defaults to hold-to-speak: key-down starts, key-up finishes, release during microphone initialization finishes as soon as the recorder is ready, and interruption cancels. On-screen microphone buttons retain click-to-start/stop behavior. The standalone hold-state checks pass.

## Visual context and connection verification

Agent requests capture the current display through ScreenCaptureKit, excluding Speek's own windows. The existing context setting controls automatic capture; dictation never captures a screen. Explicit region attachments persist across opening the assistant and starting voice input, until removed or a new task is selected. The region image is cropped from the captured display using backing-pixel coordinates.

Codex image arguments must be terminated with `--` before the prompt. Otherwise `-i` consumes the prompt and the CLI waits for stdin. Both routing and file execution use this delimiter. `scripts/checks/codex-vision.py` exercises both account environments against a generated red/blue image without transmitting user screenshots.

Connections refresh on activation and show a checked Connected state with Reconnect after successful login. Local and isolated subscription environments were verified with real image requests.

Future work: connect a Codex computer-use executor for application interaction. Keep image observation separate from action execution and approvals. No computer-use executor is implemented in this change.
