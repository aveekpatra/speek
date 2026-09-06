import SwiftUI
import AppKit

// MARK: - Tokens

enum SpeekDesign {
    static let contentMaxWidth: CGFloat = 760
    static let pagePadding: CGFloat = 24
    static let groupRadius: CGFloat = 16
    static let controlRadius: CGFloat = 10
    static let rowMinHeight: CGFloat = 54
    static let rowHorizontalPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 26

    /// Fill of a settings group card. Kept as a plain fill (never glass): glass belongs
    /// to the navigation layer, not to content cards.
    static func groupFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.065) : Color.black.opacity(0.045)
    }

    static func groupStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }

    static func rowDivider(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    static func controlFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
}

// MARK: - Page scaffold

/// Standard scrolling page: left-aligned column, generous top padding, capped width.
struct SpeekPageScroll<Content: View>: View {
    var spacing: CGFloat = SpeekDesign.sectionSpacing
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
            .frame(maxWidth: SpeekDesign.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, SpeekDesign.pagePadding)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.automatic)
    }
}

// MARK: - Section header

struct SpeekSectionHeader: View {
    let title: LocalizedStringKey
    var help: String? = nil

    init(_ title: LocalizedStringKey, help: String? = nil) {
        self.title = title
        self.help = help
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            if let help {
                SpeekHelpButton(text: help)
            }
        }
        .padding(.leading, 2)
    }
}

// MARK: - Settings group

/// Rounded card that stacks rows and draws an inset hairline between them.
struct SpeekGroup<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group(subviews: content()) { subviews in
            VStack(spacing: 0) {
                ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                    subview
                    if index < subviews.count - 1 {
                        Rectangle()
                            .fill(SpeekDesign.rowDivider(scheme))
                            .frame(height: 1)
                            .padding(.horizontal, SpeekDesign.rowHorizontalPadding)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: SpeekDesign.groupRadius, style: .continuous)
                .fill(SpeekDesign.groupFill(scheme))
                .overlay(
                    RoundedRectangle(cornerRadius: SpeekDesign.groupRadius, style: .continuous)
                        .strokeBorder(SpeekDesign.groupStroke(scheme), lineWidth: 1)
                )
        )
    }
}

/// One settings row: title (+ optional help), optional subtitle, trailing control.
struct SpeekRow<Trailing: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var help: String? = nil
    var titleColor: Color = .primary
    @ViewBuilder var trailing: () -> Trailing

    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        help: String? = nil,
        titleColor: Color = .primary,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.help = help
        self.titleColor = titleColor
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundStyle(titleColor)
                    if let help {
                        SpeekHelpButton(text: help)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, SpeekDesign.rowHorizontalPadding)
        .padding(.vertical, subtitle == nil ? 12 : 10)
        .frame(minHeight: SpeekDesign.rowMinHeight)
    }
}

extension SpeekRow where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, help: String? = nil) {
        self.init(title, subtitle: subtitle, help: help, trailing: { EmptyView() })
    }
}

/// Row whose whole surface is a button (chevron on the right).
struct SpeekNavigationRow: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SpeekRow(title, subtitle: subtitle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Help button

struct SpeekHelpButton: View {
    let text: String
    var symbol: String = "questionmark.circle"
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Text(text)
                .font(.system(size: 13))
                .frame(maxWidth: 280, alignment: .leading)
                .padding(14)
        }
    }
}

// MARK: - Pill segmented picker

/// Capsule segmented control with a tinted glass selection, e.g. Simple | Classic | Off.
struct SpeekSegmentedPicker<Option: Hashable & Identifiable>: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(SpeekDesign.controlFill(scheme)))
    }
}

// MARK: - Keycaps

/// Small rounded keycap showing a key symbol (⌥, ⇧, K, esc, Fn).
struct SpeekKeycap: View {
    @Environment(\.colorScheme) private var scheme
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(minWidth: 24)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(SpeekDesign.controlFill(scheme))
            )
    }
}

struct SpeekKeycapRow: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                SpeekKeycap(text: key)
            }
        }
    }
}

// MARK: - Icon tile (sidebar / list icons)

struct SpeekIconTile: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 26
    var symbolSize: CGFloat = 13

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Choice card (theme / recording window previews)

struct SpeekChoiceCard<Preview: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let isSelected: Bool
    var previewSize = CGSize(width: 67, height: 44)
    var cornerRadius: CGFloat = 6
    /// Tints the preview surface with the accent when selected (used for drawn previews;
    /// image thumbnails keep their own colors).
    var tintsWhenSelected = false
    let action: () -> Void
    @ViewBuilder var preview: () -> Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview()
                    .frame(width: previewSize.width, height: previewSize.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.accentColor.opacity(tintsWhenSelected && isSelected ? 0.14 : 0))
                            .allowsHitTesting(false)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius + 3, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat tile

struct SpeekStatTile: View {
    let value: String
    let label: String
    var trailingAccessory: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .contentTransition(.numericText())
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                if let trailingAccessory { trailingAccessory }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Buttons

/// Secondary pill button used for "Add apps and sites", "Check for Updates...".
struct SpeekPillButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 14))
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
    }
}

/// Small circular download / installed indicator used in the Models library.
struct SpeekCircleIconButton: View {
    let systemName: String
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.small)
    }
}

// MARK: - Speed / accuracy meter

/// Five dashes with `filled` of them highlighted, mirroring Superwhisper's meter.
struct SpeekMeter: View {
    let value: Double // 0...1
    var segments: Int = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Double(index) < value * Double(segments) - 0.01 ? Color.secondary : Color.secondary.opacity(0.28))
                    .frame(width: 18, height: 2.5)
            }
        }
    }
}

// MARK: - Misc helpers

extension View {
    /// Reads the row as a plain, full-width tappable surface with hover feedback.
    func speekHoverHighlight(cornerRadius: CGFloat = 12) -> some View {
        modifier(SpeekHoverHighlight(cornerRadius: cornerRadius))
    }
}

private struct SpeekHoverHighlight: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let cornerRadius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(hovering ? SpeekDesign.controlFill(scheme).opacity(0.7) : Color.clear)
            )
            .onHover { hovering = $0 }
    }
}

// MARK: - Model icons

enum SpeekModelIcon {
    /// Brand tiles for local model providers (logo assets are template SVGs).
    enum Brand {
        case apple, nvidia, cohere, openAI, ollama, superwhisper

        var assetName: String? {
            switch self {
            case .apple: return "provider-apple"
            case .nvidia: return "provider-nvidia"
            case .cohere: return "provider-cohere"
            case .openAI: return "provider-openai"
            case .ollama: return "provider-ollama"
            case .superwhisper: return nil
            }
        }

        var background: Color {
            switch self {
            case .apple: return Color(white: 0.12)
            case .nvidia: return Color(red: 0.46, green: 0.73, blue: 0.0)
            case .cohere: return Color(red: 0.22, green: 0.35, blue: 0.30)
            case .openAI: return Color(white: 0.10)
            case .ollama: return Color(white: 0.96)
            case .superwhisper: return Color(red: 0.25, green: 0.45, blue: 0.95)
            }
        }

        var foreground: Color {
            switch self {
            case .ollama: return Color(white: 0.10)
            default: return .white
            }
        }
    }

    static func brand(for provider: ModelProvider?) -> Brand {
        switch provider {
        case .cohere: return .cohere
        case .canary, .fluidAudio: return .nvidia
        case .whisper: return .openAI
        case .nativeApple: return .apple
        default: return .openAI
        }
    }

    static func tile(for provider: ModelProvider?, size: CGFloat = 20) -> some View {
        tile(brand: brand(for: provider), size: size)
    }

    /// Gray tile with a symbol, for "None"/placeholder entries.
    static func neutralTile(symbol: String, size: CGFloat = 20) -> some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color(white: 0.4))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
    }

    static func tile(brand: Brand, size: CGFloat = 20) -> some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(brand.background)
            .frame(width: size, height: size)
            .overlay(
                Group {
                    if let asset = brand.assetName {
                        Image(asset)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size * 0.58, height: size * 0.58)
                    } else {
                        Image(systemName: "waveform.and.mic")
                            .font(.system(size: size * 0.5, weight: .semibold))
                    }
                }
                .foregroundStyle(brand.foreground)
            )
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

// MARK: - Model popup

/// Popup-style picker whose label shows a real icon tile (system menus flatten custom views).
struct SpeekModelPopup: View {
    struct Option: Identifiable {
        let id: String
        let title: String
        let icon: AnyView
    }

    @Environment(\.colorScheme) private var scheme
    let title: String
    let icon: AnyView
    let options: [Option]
    let selectedID: String
    let onSelect: (String) -> Void
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                icon
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 150, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SpeekDesign.controlFill(scheme)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options) { option in
                    Button {
                        onSelect(option.id)
                        isPresented = false
                    } label: {
                        HStack(spacing: 8) {
                            option.icon
                            Text(option.title)
                                .font(.system(size: 13))
                                .lineLimit(1)
                            Spacer(minLength: 12)
                            if option.id == selectedID {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .speekHoverHighlight(cornerRadius: 8)
                }
            }
            .padding(6)
            .frame(minWidth: 240)
        }
    }
}
