import SwiftUI
import AppKit

/// About: version, update, links, credits.
struct AboutPage: View {
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        SpeekPageScroll {
            SpeekGroup {
                HStack(alignment: .top, spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Speek")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Version \(version)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Free and open source dictation. Every model runs on your Mac; nothing leaves it.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        HStack(spacing: 8) {
                            Button("Check for Updates...") { updaterViewModel.checkForUpdates() }
                            Button {
                                NSWorkspace.shared.open(SpeekLinks.repository)
                            } label: {
                                Label("Star on GitHub", systemImage: "star")
                            }
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.regular)
                        .padding(.top, 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(SpeekDesign.rowHorizontalPadding)
            }

            VStack(alignment: .leading, spacing: 10) {
                SpeekSectionHeader("Speek is a fork of")
                SpeekGroup {
                    creditRow("Whisper Pro", "Zdenek Culik. Speek was forked from here, GPL-3.0", url: "https://github.com/ZdenekCulik/whisper-pro")
                    creditRow("VoiceInk", "Prakash Joshi Pax. Whisper Pro was forked from here, GPL-3.0", url: "https://github.com/Beingpax/VoiceInk")
                }
                Text("Speek keeps the GPL-3.0 license of both projects and credits every author in that chain.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: 10) {
                SpeekSectionHeader("Bundled libraries")
                SpeekGroup {
                    creditRow("whisper.cpp", "Georgi Gerganov and contributors, MIT", url: "https://github.com/ggerganov/whisper.cpp")
                    creditRow("llama.cpp", "Georgi Gerganov and contributors, MIT", url: "https://github.com/ggerganov/llama.cpp")
                    creditRow("FluidAudio", "FluidInference, Apache 2.0", url: "https://github.com/FluidInference/FluidAudio")
                    creditRow("Sparkle", "Sparkle Project, MIT", url: "https://github.com/sparkle-project/Sparkle")
                    creditRow("swift-markdown-ui", "Guillermo Gonzalez, MIT", url: "https://github.com/gonzalezreal/swift-markdown-ui")
                    creditRow("LaunchAtLogin-Modern", "Sindre Sorhus, MIT", url: "https://github.com/sindresorhus/LaunchAtLogin-Modern")
                    creditRow("AXSwift", "Tyler Mandry and contributors, MIT", url: "https://github.com/tisfeng/AXSwift")
                    creditRow("KeySender", "Jordan Baird, MIT", url: "https://github.com/jordanbaird/KeySender")
                    creditRow("Zip", "Roy Marmelstein, MIT", url: "https://github.com/marmelroy/Zip")
                    creditRow("LLMkit, SelectedTextKit, mediaremote-adapter", "Prakash Joshi Pax", url: "https://github.com/Beingpax")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SpeekSectionHeader("Models you can download")
                SpeekGroup {
                    creditRow("Cohere Transcribe", "Cohere Labs", url: "https://huggingface.co/CohereLabs/cohere-transcribe-03-2026")
                    creditRow("Parakeet and Canary", "NVIDIA, CC BY 4.0", url: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3")
                    creditRow("Whisper", "OpenAI, MIT", url: "https://github.com/openai/whisper")
                    creditRow("S1-mini", "Superwhisper", url: "https://huggingface.co/superwhisper/s1-mini")
                }
                Text("Not part of Speek. Each model is fetched from its authors when you choose it and stays under its own license.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: 10) {
                SpeekSectionHeader("Support the project")
                SpeekGroup {
                    SpeekRow("Speek is free", subtitle: "Funding options will appear here. For now, a star or a bug report on GitHub helps most.") {
                        Button("Open GitHub") { NSWorkspace.shared.open(SpeekLinks.repository) }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                    }
                }
            }

            Spacer(minLength: 40)

            HStack(spacing: 10) {
                Spacer()
                linkButton("Roadmap", symbol: "map", url: SpeekLinks.issues)
                linkButton("Report a bug", symbol: "ladybug", url: SpeekLinks.issues)
                linkButton("GitHub", symbol: "chevron.left.forwardslash.chevron.right", url: SpeekLinks.repository)
            }
        }
        .navigationTitle("")
        .toolbar { SpeekStandardToolbar() }
    }

    private func creditRow(_ name: String, _ detail: String, url: String) -> some View {
        Button {
            if let link = URL(string: url) { NSWorkspace.shared.open(link) }
        } label: {
            SpeekRow(LocalizedStringKey(name), subtitle: LocalizedStringKey(detail)) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func linkButton(_ title: String, symbol: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    }
}
