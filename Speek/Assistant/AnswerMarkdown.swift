import SwiftUI
import AppKit
import MarkdownUI

/// Assistant answers with full formatting: headings, lists, tables, code, links.
struct AnswerMarkdown: View {
    let text: String
    var size: CGFloat = 14

    var body: some View {
        Markdown(text)
            .markdownTheme(Self.theme(size: size))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func theme(size: CGFloat) -> Theme {
        Theme()
            .text {
                ForegroundColor(.white.opacity(0.86))
                FontSize(size)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.9))
                BackgroundColor(.white.opacity(0.08))
            }
            .strong { FontWeight(.semibold) }
            .link { ForegroundColor(.accentColor) }
            .heading1 { configuration in
                configuration.label.markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.35)); ForegroundColor(.white) }
                    .markdownMargin(top: 14, bottom: 8)
            }
            .heading2 { configuration in
                configuration.label.markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.2)); ForegroundColor(.white) }
                    .markdownMargin(top: 12, bottom: 6)
            }
            .heading3 { configuration in
                configuration.label.markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.05)); ForegroundColor(.white) }
                    .markdownMargin(top: 10, bottom: 4)
            }
            .paragraph { configuration in
                configuration.label.lineSpacing(5).markdownMargin(top: 0, bottom: 10)
            }
            .listItem { configuration in
                configuration.label.markdownMargin(top: 3)
            }
            .codeBlock { configuration in
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .markdownTextStyle { FontFamilyVariant(.monospaced); FontSize(.em(0.85)) }
                        .padding(12)
                }
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .markdownMargin(top: 4, bottom: 12)
            }
            .blockquote { configuration in
                configuration.label
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.25)).frame(width: 2) }
                    .markdownMargin(top: 4, bottom: 10)
            }
            .table { configuration in
                configuration.label
                    .markdownTableBorderStyle(.init(color: .white.opacity(0.15)))
                    .markdownMargin(top: 4, bottom: 12)
            }
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle { if configuration.row == 0 { FontWeight(.semibold) } }
                    .padding(.vertical, 5).padding(.horizontal, 10)
            }
    }
}

struct CopyAnswerButton: View {
    let text: String
    @State private var copied = false
    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            copied = NSPasteboard.general.setString(text, forType: .string)
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11)).foregroundStyle(.white)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Copy").accessibilityLabel(copied ? "Copied" : "Copy answer")
    }
}

/// Puts an answer into the text field you were last working in (for drafts, replies, notes).
struct InsertAnswerButton: View {
    let text: String
    @ObservedObject private var focus = VoiceFocus.shared
    var body: some View {
        if let app = focus.lastExternalAppName {
            Button { AssistantController.shared.insertAnswer(text) } label: {
                Image(systemName: "text.insert").font(.system(size: 11)).foregroundStyle(.white)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Insert into " + app).accessibilityLabel("Insert into " + app)
        }
    }
}
