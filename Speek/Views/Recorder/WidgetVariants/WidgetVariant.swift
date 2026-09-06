import SwiftUI

/// Read-only snapshot of everything a mini-widget variant needs to render.
/// Passing one struct keeps every variant's init identical and stable, so
/// variant files can be authored independently without touching shared code.
struct WidgetVariantContext {
    let committed: String      // stabilized transcript (won't change)
    let partial: String        // still-revising tail
    let audioMeter: AudioMeter // live audio levels for the waveform
    let recordingState: RecordingState
    var isCancelConfirming: Bool = false // first Escape: show confirm overlay
    var isCanceling: Bool = false        // second Escape: play dissolve + close
    /// Set while the "⌘V to paste" hint is showing (paste couldn't auto-land). Variants
    /// that support it (V2) morph their own container into a small pill instead of a
    /// separate view being swapped in — see MiniRecorderView.
    var pasteHintText: String? = nil

    var isRecording: Bool { recordingState == .recording }
    var hasText: Bool { !committed.isEmpty || !partial.isEmpty }
}

/// The selectable mini-widget looks. Trimmed down from the original V1–V25
/// prototype sweep to the two keepers. Raw values are kept at their original
/// numbers (2/16) since they're persisted in UserDefaults; a persisted value that no
/// longer matches a case (e.g. the removed V9 "Compact") falls back to .v2 in
/// WidgetVariantStore's init below.
enum WidgetVariant: Int, CaseIterable, Identifiable {
    case v2 = 2
    case v16 = 16

    var id: Int { rawValue }
    var label: String { "V\(rawValue)" }

    /// Short, macOS-style name shown in the Settings preview cards.
    var displayName: String {
        switch self {
        case .v2: return "Classic"
        case .v16: return "Minimal"
        }
    }

    @MainActor @ViewBuilder
    func makeView(_ context: WidgetVariantContext) -> some View {
        switch self {
        case .v2:  Variant2View(context: context)
        case .v16: Variant16View(context: context)
        }
    }
}

/// Holds the currently selected variant, shared by the widget and the cycle badge.
@MainActor
final class WidgetVariantStore: ObservableObject {
    static let shared = WidgetVariantStore()
    private static let key = "MiniWidgetVariant"

    @Published var variant: WidgetVariant {
        didSet { UserDefaults.standard.set(variant.rawValue, forKey: Self.key) }
    }

    private init() {
        let raw = UserDefaults.standard.integer(forKey: Self.key)
        variant = WidgetVariant(rawValue: raw) ?? .v2
    }

    /// Cycle to the next variant (wraps around). Used by the temporary badge.
    func next() {
        let all = WidgetVariant.allCases
        let idx = all.firstIndex(of: variant) ?? 0
        variant = all[(idx + 1) % all.count]
    }
}
