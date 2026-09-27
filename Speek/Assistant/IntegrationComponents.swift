import SwiftUI
import AppKit

/// Layout rule for Integrations: what Speek ships is a grouped list (finite, scan for on/off);
/// what the user adds is a grid of equal tiles (open-ended, browse like a shelf).

/// Section heading with an optional explanation and a trailing add action.
struct IntegrationSectionHeader<Action: View>: View {
    let title: String
    var info: String? = nil
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let info { InfoButton(text: info, subject: title) }
            Spacer(minLength: 16)
            action
        }.padding(.leading, 4)
    }
}

extension IntegrationSectionHeader where Action == EmptyView {
    init(title: String, info: String? = nil) { self.init(title: title, info: info) { EmptyView() } }
}

/// Equal-height tile for user-added integrations. Tap opens details; the menu appears on hover.
struct IntegrationTile<Control: View, MenuItems: View>: View {
    let symbol: String
    var asset: String? = nil
    let title: String
    let subtitle: String
    let status: String
    var statusSymbol = "circle"
    var busy = false
    var showsMenu = true
    let open: () -> Void
    @ViewBuilder var control: Control
    @ViewBuilder var menu: MenuItems
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var height: CGFloat { 184 }
    static var columns: [GridItem] { [GridItem(.adaptive(minimum: 230, maximum: 420), spacing: 16, alignment: .top)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                IntegrationGlyph(symbol: symbol, asset: asset)
                Spacer(minLength: 8)
                if showsMenu {
                    Menu { menu } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28).contentShape(Rectangle()) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help(title + " actions").accessibilityLabel(title + " actions")
                        .opacity(hovered ? 1 : 0).allowsHitTesting(hovered)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    if busy { ProgressView().controlSize(.mini) } else { Image(systemName: statusSymbol) }
                    Text(status).lineLimit(1)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                control
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .topLeading)
        .settingsSurface()
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture(perform: open)
        .onHover { value in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { hovered = value } }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open " + title, open)
    }
}

/// Placeholder that keeps an empty shelf the same shape as a filled one.
struct IntegrationEmptyTile: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        LazyVGrid(columns: IntegrationTile<EmptyView, EmptyView>.columns, alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                IntegrationGlyph(symbol: symbol)
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: IntegrationTile<EmptyView, EmptyView>.height, alignment: .topLeading)
            .settingsSurface()
        }
    }
}

struct IntegrationGlyph: View {
    let symbol: String
    /// A brand mark from the asset catalog, used instead of the symbol when present.
    var asset: String? = nil
    var body: some View {
        Group {
            if let asset {
                Image(asset).resizable().renderingMode(.template).scaledToFit().frame(width: 22, height: 22)
            } else {
                Image(systemName: symbol).font(.system(size: 22))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 44, height: 44).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The installed app's own icon, so native integrations read like System Settings.
enum AppIcon {
    private static var cache: [String: NSImage] = [:]
    static func image(for bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}
