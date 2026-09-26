import SwiftUI

struct DictationSettingsView: View {
    @AppStorage("speek.dictation.polish") private var polish = DictationPolish.raw.rawValue
    @AppStorage("speek.dictation.contextual") private var contextual = true
    @AppStorage("speek.dictation.style") private var style = "Natural"
    @AppStorage("speek.dictation.editSelectedText") private var editSelectedText = false
    private var mode: DictationPolish { DictationPolish(rawValue: polish) ?? .raw }

    var body: some View {
        SettingsSection(title: "Writing and editing") {
            SettingsRow(title: "Writing mode", info: "Raw keeps your words and applies saved vocabulary. Light cleans up punctuation, fillers, and repeats. Polished shapes clear writing for the destination. If polishing fails, the original dictation is kept.") {
                Picker("Writing mode", selection: $polish) {
                    ForEach(DictationPolish.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }.labelsHidden()
            }
            if mode == .polished {
                SettingsRowDivider()
                SettingsRow(title: "Match the destination", info: "Adapt formatting for mail, messages, and notes based on the app.") {
                    Toggle("Match the destination", isOn: $contextual).labelsHidden().toggleStyle(.switch)
                }
                SettingsRowDivider()
                SettingsRow(title: "Writing style") {
                    Picker("Writing style", selection: $style) {
                        ForEach(["Natural", "Concise", "Professional", "Friendly"], id: \.self) { Text($0).tag($0) }
                    }.labelsHidden()
                }
            }
            SettingsRowDivider()
            SettingsRow(title: "Edit selected text by voice", info: "With text selected, dictation becomes an editing instruction. Speek replaces the text only if the selection is unchanged.") {
                Toggle("Edit selected text by voice", isOn: $editSelectedText).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}
