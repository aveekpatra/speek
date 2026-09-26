# Connection choices

Updated 2026-09-26.

- Codex on this Mac reuses the installed CLI login.
- ChatGPT subscription uses Codex browser login with an isolated Speek CODEX_HOME under Application Support. It shares the account subscription allowance, not a separate quota.
- OpenRouter uses the saved API key and configurable routing model.
- Each task saves its connection. Switching clears the pending action and execution session. Recent messages and explicit context are sent to the selected provider.
- Voice defaults to OpenRouter. An existing OpenAI Platform key can optionally be selected for voice. No silent provider fallback occurs.
- Codex routing uses ephemeral, read-only CLI calls with a JSON output schema. Project execution requires a reviewed action and selected directory, with workspace-write sandboxing.
- Browser sign-in is completed by the user. Authentication is managed by Codex; Speek never parses cached credentials.
- No local language model is used.

## Earlier implementation notes

The notes below describe the initial implementation; the connection choices above supersede provider defaults and fallback behavior.

# Speek voice actions

## Product direction

Speek is moving from a dictation-first app to a voice and text task workspace. A request becomes a proposed action, the user reviews it, and Speek executes it with a named integration. Offline dictation remains available for people who want it, but it is no longer the main entry point.

VoiceOS is a useful reference for three product layers: input, desktop context, and actions. Its official material describes actions across connected apps, confirmation before consequential writes, and local Codex or Claude Code dispatch through the user's CLI. See [VoiceOS overview](https://www.voiceos.com/), [integrations](https://www.voiceos.com/app-store), and [voice coding](https://www.voiceos.com/use-cases/voice-coding-for-developers).

Speek should keep its own character: a compact task desk inside the existing macOS app, explicit tool availability, local task history, and direct control over each project folder. We should not copy VoiceOS's visual identity or imply that an unconnected service works.

## Current implementation

The Workspace page is the primary home screen. It accepts typed requests or a bounded voice recording. Direct OpenAI is preferred for transcription, request routing, and speech synthesis. OpenRouter is an alternative and can handle requests when a direct OpenAI key is unavailable or a request fails. The router returns one of four results: open a public HTTPS website, search the web, run a local Codex task, or answer in the thread. Unsupported app requests explain which integration is missing. Open, search, and Codex actions show a review card before running. Assistant messages have a Read aloud control. The macOS system voice is a last resort for speech output.

Task threads are saved in Application Support as JSON. The online router receives only the last eight local messages, each trimmed to 700 characters, plus context notes the user explicitly saves for the task. Codex session IDs, project paths, and context notes are saved per task, so later coding requests in the same task resume that session. Audio is recorded to a temporary WAV file and removed after transcription.

The Codex CLI starts only after the user reviews a proposed coding task and chooses an existing project folder. It uses the `workspace-write` sandbox and a noninteractive approval policy. The CLI gets the prompt as an argument, without a shell. This is a workspace boundary for Codex commands, not a general process isolation boundary for all of Speek.

Users can enter their own direct OpenAI or OpenRouter key through Speek's existing Keychain credential manager. Local development keys can also be read from `OPENAI_API_KEY` and `OPENROUTER_API_KEY` in the process environment or `~/Library/Application Support/com.aveekpatra.speek/.env.local`, outside the repository. A Keychain key wins over the environment file. OpenAI is preferred unless the user selects OpenRouter. If the preferred provider lacks a key or fails, the other cloud provider handles the request when connected. The direct OpenAI Responses request sets `store: false`. Codex CLI authentication is used for coding tasks and does not authorize direct OpenAI audio API calls. The macOS build no longer links or embeds llama.cpp and no longer includes S1-mini download or execution code. Offline speech recognition remains optional.

## Next increments

1. Add a real integration registry with typed action schemas, connection state, and per-action review rules. Start with Calendar and Reminders, then cloud services through OAuth or MCP.
2. Add a context picker for selected text, active app, browser URL, and an optional screenshot. Show exactly what will be sent with each request. Do not add screen content to prompts silently.
3. Make Codex jobs observable and cancellable. Show running steps, approval requests, changed files, and the final diff. Add a per-project execution policy and an isolated worktree option.
4. Add model discovery and capability validation to provider settings so speech voices and response formats stay compatible with the chosen model.
5. Move legacy dictation and offline model controls into a clear optional section after the action loop is stable.

## Design notes

The desk uses a narrow task rail and a broad request canvas. The request composer stays visible while a task runs. The only saturated accent marks actionable controls and the pending review card. A task's available tools are stated in plain language on an empty thread. Recording, processing, review, and completion each have distinct text, so color alone never carries state.
