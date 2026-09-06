import SwiftUI
import AppKit

/// Floating Liquid Glass mode switcher, shown by the "Change mode" shortcut (⌥⇧K by
/// default). Click a mode or press its number; Escape closes.
@MainActor
final class ModeSwitcherController {
    static let shared = ModeSwitcherController()

    private var panel: NSPanel?
    private var observer: NSObjectProtocol?

    private init() {}

    func start() {
        observer = NotificationCenter.default.addObserver(forName: .speekShowModeSwitcher, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.toggle() }
        }
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            let panel = ModeSwitcherNSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.onEscape = { [weak self] in self?.close() }
            panel.onDigit = { [weak self] digit in self?.select(index: digit - 1) }
            panel.contentView = NSHostingView(rootView: ModeSwitcherView(onSelect: { [weak self] config in
                ModeManager.shared.setActiveConfiguration(config)
                self?.close()
            }))
            self.panel = panel
        }
        guard let panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2 + 60)
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func select(index: Int) {
        let modes = ModeManager.shared.enabledConfigurations
        guard modes.indices.contains(index) else { return }
        ModeManager.shared.setActiveConfiguration(modes[index])
        close()
    }
}

private final class ModeSwitcherNSPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onDigit: ((Int) -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?(); return }
        if let chars = event.charactersIgnoringModifiers, let digit = Int(chars), (1...9).contains(digit) {
            onDigit?(digit)
            return
        }
        super.keyDown(with: event)
    }

    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}

private struct ModeSwitcherView: View {
    @ObservedObject private var modeManager = ModeManager.shared
    let onSelect: (ModeConfig) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Change mode")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ForEach(Array(modeManager.enabledConfigurations.enumerated()), id: \.element.id) { index, config in
                Button {
                    onSelect(config)
                } label: {
                    HStack(spacing: 10) {
                        ModeIconView(icon: config.icon, size: 13, color: .primary)
                            .frame(width: 18)
                        Text(config.name)
                            .font(.system(size: 14))
                        Spacer()
                        if modeManager.currentEffectiveConfiguration?.id == config.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        if index < 9 {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.1)))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .speekHoverHighlight(cornerRadius: 10)
                .padding(.horizontal, 4)
            }
            Spacer(minLength: 6)
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(20)
    }
}
