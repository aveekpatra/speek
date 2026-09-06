import SwiftUI

struct SpeekSidebar: View {
    @ObservedObject var navigation: SpeekNavigation

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(SpeekPage.sidebarSections.enumerated()), id: \.offset) { index, section in
                        if index > 0 {
                            Color.clear.frame(height: 14)
                        }
                        ForEach(section) { page in
                            SidebarRow(page: page, isSelected: navigation.page == page) {
                                navigation.open(page)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)

            footer
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Quiet footer: version plus a Credits link. Speek sells nothing, so no call to action here.
    private var footer: some View {
        HStack(spacing: 0) {
            Text("Speek \(version)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            footerLink("Credits", isCurrent: navigation.page == .about, help: "Version, credits and licenses") {
                navigation.open(.about)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private func footerLink(_ title: String, isCurrent: Bool, help: String, action: @escaping () -> Void) -> some View {
        FooterLink(title: title, isCurrent: isCurrent, help: help, action: action)
    }
}

private struct SidebarRow: View {
    @Environment(\.colorScheme) private var scheme
    let page: SpeekPage
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                SpeekIconTile(systemName: page.systemImage, color: page.tileColor, size: 24, symbolSize: 12)
                Text(page.title)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 7)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(scheme == .dark ? 0.16 : 0.10) : (hovering ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Small text link for the sidebar footer; underlines on hover.
private struct FooterLink: View {
    let title: String
    let isCurrent: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                .underline(hovering, color: .secondary)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
