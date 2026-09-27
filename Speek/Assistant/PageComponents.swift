import SwiftUI

/// Neutral pill tabs shared by Memory, Integrations, and Settings.
struct PillTabs: View {
    let items: [String]
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { selection = item }
                } label: {
                    Text(item).font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(selection == item ? Color.white.opacity(0.11) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }.padding(4).frame(maxWidth: CGFloat(items.count) * 105).background(.black.opacity(0.14), in: Capsule())
    }
}

/// Compact search that sits in a section header, styled like the flat action buttons.
struct SpeekSearchField: View {
    let prompt: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.white)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 13)).focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.white) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10).frame(width: 220, height: 30)
        .background(.white.opacity(focused ? 0.11 : 0.075), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}

/// Edit and delete controls that appear only while the row is hovered.
struct HoverRowActions: View {
    let visible: Bool
    let subject: String
    var edit: (() -> Void)? = nil
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            if let edit {
                Button(action: edit) { Image(systemName: "pencil").font(.system(size: 13)).frame(width: 28, height: 28).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help("Edit").accessibilityLabel("Edit " + subject)
            }
            Button(action: remove) { Image(systemName: "trash").font(.system(size: 13)).frame(width: 28, height: 28).contentShape(Rectangle()) }
                .buttonStyle(.plain).help("Delete").accessibilityLabel("Delete " + subject)
        }
        .foregroundStyle(.white)
        .opacity(visible ? 1 : 0).allowsHitTesting(visible)
    }
}
