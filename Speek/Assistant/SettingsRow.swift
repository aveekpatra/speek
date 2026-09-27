import SwiftUI
import AppKit

/// A titled group of settings rows on the shared settings surface.
struct SettingsSection<Content: View>: View {
    let title: String
    var info: String? = nil
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let info { InfoButton(text: info, subject: title) }
            }.padding(.leading, 4)
            VStack(spacing: 0) { content }.settingsSurface()
        }
    }
}

/// macOS form row: label leading, control trailing on the same line.
/// `value` is live state (a path, an error, a count), never an explanation.
/// Explanations go behind the info button so rows stay scannable.
struct SettingsRow<Control: View>: View {
    let title: String
    var icon: String? = nil
    /// A real app icon or brand mark, shown in the same slot as `icon`.
    var image: NSImage? = nil
    var asset: String? = nil
    var value: String? = nil
    var info: String? = nil
    /// When set, the row expands to show more (such as its tools) with a trailing chevron.
    var expanded: Binding<Bool>? = nil
    @ViewBuilder var control: Control
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).frame(width: 28, height: 28).frame(width: 28, height: 32)
            } else if let asset {
                Image(asset).resizable().scaledToFit().foregroundStyle(.white).frame(width: 22, height: 22).frame(width: 28, height: 32)
            } else if let icon {
                Image(systemName: icon).font(.system(size: 19)).foregroundStyle(.white).frame(width: 28, height: 32)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if let info { InfoButton(text: info, subject: title) }
                }
                if let value, !value.isEmpty {
                    Text(value).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }
            }
            Spacer(minLength: 24)
            control.fixedSize()
            if let expanded {
                Button { toggle(expanded) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
                        .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0)).frame(width: 20, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(expanded.wrappedValue ? "Hide tools" : "Show tools")
            }
        }
        .padding(16)
        .contentShape(Rectangle())
        .onTapGesture { if let expanded { toggle(expanded) } }
    }
}

extension SettingsRow {
    private func toggle(_ binding: Binding<Bool>) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { binding.wrappedValue.toggle() }
    }
}

struct SettingsRowDivider: View {
    /// Rows with a leading icon indent the divider past the icon.
    var leading: CGFloat = 16
    var body: some View { Divider().padding(.leading, leading).padding(.trailing, 16) }
}

/// Explains a setting on hover (tooltip) or click (popover).
struct InfoButton: View {
    let text: String
    var subject = ""
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(.white)
                .frame(width: 16, height: 16).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text)
        .accessibilityLabel(subject.isEmpty ? "More information" : "About " + subject)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text).font(.system(size: 12))
                .frame(width: 260, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                .padding(12)
        }
    }
}
