# Speek

Speek is a voice assistant for your Mac that lives in the notch. Hold a key and talk: it types what you say into any app, or it does what you ask, using your apps, your accounts, and what is on your screen.

<!-- Screenshots will be added here. -->

## What you can do with it

**Write without typing.** Hold the shortcut, speak, let go. Your words appear in whatever text field you are in: Mail, Slack, Notes, a browser, a terminal. Speek fits the text into what is already there (spacing, capitals), formats it for the app you are in, and can polish it into clean sentences.

**Ask for things out loud.** "Reply to Tomas that Friday works." "What's on my calendar tomorrow?" "Play Faded by Alan Walker." "Unsubscribe me from this newsletter." Speek works out what to do, uses the right app or service, and answers in the notch, or reads the answer aloud.

**Point at your screen.** Speek sees the screen you are looking at when you ask. To point at something specific, circle it with the pointer while you hold the shortcut: a stroke follows your pointer, and "this" means what you circled.

**Let it work while you keep going.** Ask something new while a task is still running and the first one keeps going in the background. When it finishes, a notice appears in the notch, and the result waits in its conversation.

**Have it remember.** Say "remember my sister's name is Priya" or "remember I prefer meetings after 11". Speek keeps it and uses it when it matters. Say "forget ..." to remove something. Lock the things that should always be true.

## Features

### Dictation
- Hold-to-speak shortcut, a double-tap for hands-free, or a mouse button.
- Raw, light cleanup, or polished writing, with a writing style you choose.
- Writing adapts to the app you are in and to the text around your cursor.
- Edit selected text by voice: select, then say "make this shorter" or "translate to Czech".
- A live transcript while you speak.
- Vocabulary for names and terms, including spoken shortcuts and bulk import.
- Learns from your corrections: fix a misheard name right after dictating, and Speek remembers it, with Undo.
- Several recognition languages.
- Dictation history with one-click copy, and optional recovery of recordings that failed.

### The assistant
- A notch panel that stays out of the way, and a main window for longer conversations.
- Conversations start and continue on their own: a follow-up within a few minutes continues the conversation, a new topic later starts a new one.
- Background tasks that report back, and approvals you answer right in the notch.
- Screen context with each request (can be turned off), a circle gesture to point, and "look at my screen" on demand.
- Attach images, PDFs, and text files by dropping or pasting them into the notch.
- Answers you can copy, insert into the app you were using, or have read aloud.
- Reusable prompts and schedules for recurring requests.
- Choice of model and provider (OpenRouter, OpenAI, or a local Codex login).

### Your Mac and apps
- **Mail and Messages:** search, read, draft, reply, send, file, and mark messages.
- **Calendar and Reminders:** find free time, create and change events and reminders.
- **Notes:** search, read, create, and add to notes.
- **Music and Spotify:** play, pause, skip, search, playlists, and your library.
- **Media keys and volume:** play, pause, and skip in whatever is playing, and set the volume.
- **Files:** read and organize files in a working folder you choose.
- **Computer use:** when no connected tool can do something, Speek operates the app on screen for you: clicking, typing, and navigating.
- **Shell:** runs command-line tools you already use, such as the GitHub CLI.

### Connected services
- Plugins through the Model Context Protocol, with one-click sign-in: Gmail, Google Calendar, GitHub, Notion, Linear, LexyOS, Aturno, and hundreds more through Composio.
- Add any remote or local MCP server, and your own command-line tools.
- Skills: written instructions that teach Speek how to use a tool well.
- Replies for coding assistants: when Claude Code or Codex finishes or needs you, Speek shows it and lets you answer by voice.

### Memory
- Facts you ask it to remember, locked preferences that are always used, procedures for recurring work, and a history of past requests.
- Recall that understands meaning, not just matching words.
- Everything is visible and editable in Memory.

### Control and privacy
- Choose per tool whether Speek asks first, always runs it, or never uses it.
- Settings for saving history, and a pause for dictation in password fields.
- Plugin sign-ins and memory are stored on your Mac.

## Requirements

- macOS 26 on a Mac. Speek is built for the Mac only.
- An OpenRouter or OpenAI API key for voice and the assistant. Computer use also needs Codex installed and signed in.
- Permissions, asked for when a feature first needs them: Microphone, Accessibility, Screen Recording, and access to the apps you connect.

## Getting started

1. Open Speek and go to **Models & Voice** to add your API key.
2. Grant Microphone and Accessibility when asked.
3. Hold the shortcut (Option-Space by default) and talk.
4. Turn on the apps and services you want under **Integrations**.

## For developers

Speek builds with Xcode 26. `./scripts/dev-build.sh` builds, signs with the stable development identity, and installs to `/Applications/Speek.app`. Checks live in `scripts/checks/`. [Feature status](docs/FEATURE_STATUS.md) lists supported paths and known limits, and [PRD.md](PRD.md) describes current behavior.

## Acknowledgments

Speek builds on the work of these open-source projects:

- [VoiceInk](https://github.com/Beingpax/VoiceInk) by Prakash Joshi Pax (GPL-3.0)
- [Whisper Pro](https://github.com/ZdenekCulik/whisper-pro) by Zdenek Culik (GPL-3.0)
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp), [FluidAudio](https://github.com/FluidInference/FluidAudio), [Sparkle](https://github.com/sparkle-project/Sparkle), [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui), [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern), [AXSwift](https://github.com/tisfeng/AXSwift), [KeySender](https://github.com/jordanbaird/KeySender), [Zip](https://github.com/marmelroy/Zip), and LLMkit, SelectedTextKit, and mediaremote-adapter by Prakash Joshi Pax
- Speech models from NVIDIA (Parakeet, Canary), OpenAI (Whisper), and Cohere, each under its own license
- Avo by Aristu Sachdev, studied as an interaction reference

## License

Speek is free software under the GNU General Public License v3.0. See [LICENSE](LICENSE).
