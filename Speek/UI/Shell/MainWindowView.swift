import SwiftUI

/// The main window: Liquid Glass sidebar + detail column.
struct MainWindowView: View {
    var body: some View { AssistantSettingsView() }
}

/// Toolbar shared by most pages: microphone picker on the trailing edge.
struct SpeekStandardToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarSpacer(.flexible)
        ToolbarItem(placement: .primaryAction) {
            MicrophoneToolbarMenu()
        }
    }
}

/// Right-aligned search field (plus optional extra controls) for list pages.
struct SpeekSearchToolbar<Extra: View>: ToolbarContent {
    @Binding var text: String
    let prompt: String
    @ViewBuilder var extra: () -> Extra

    init(text: Binding<String>, prompt: String, @ViewBuilder extra: @escaping () -> Extra) {
        _text = text
        self.prompt = prompt
        self.extra = extra
    }

    var body: some ToolbarContent {
        ToolbarSpacer(.flexible)
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .frame(width: 200)
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
        }
        // Fixed spacer: keeps the extra control in its own glass group instead of
        // merging into the search field's capsule.
        ToolbarSpacer(.fixed)
        ToolbarItem(placement: .primaryAction) {
            extra()
        }
    }
}

extension SpeekSearchToolbar where Extra == EmptyView {
    init(text: Binding<String>, prompt: String) {
        self.init(text: text, prompt: prompt, extra: { EmptyView() })
    }
}
