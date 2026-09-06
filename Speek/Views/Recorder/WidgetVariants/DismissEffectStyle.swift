import Foundation

/// The Escape/cancel dismiss animation for the mini recorder panel (V2 only). Picked in
/// Settings → Interface. Only the second-Escape cancel path uses this — a normal
/// successful dismiss (paste succeeded) keeps the plain reveal/dismiss fade from
/// MiniWindowManager untouched.
///
/// Craft rule for every case: one effect language, staged sequentially (phase B starts
/// only once phase A finishes), nothing pops — every element that disappears has its
/// own exit, and the whole choreography stays under ~1s.
///
/// Numbering: V2 ("poof") was removed after user feedback. The remaining cases keep
/// their ORIGINAL labels (V1, V3, V4) rather than renumbering — the user refers to them
/// by these numbers — so `label` is explicit per case instead of derived from
/// `rawValue`. Raw values are also kept stable for existing UserDefaults; `resolved`
/// migrates a stored legacy V2 (poof) selection to V4 instead of silently falling back
/// to the new default.
enum DismissEffectStyle: Int, CaseIterable, Identifiable {
    /// Phase 1: the transcript text AND the waveform row both dissolve into dust
    /// (InvisibleInkText / BarDustView). Phase 2, once phase 1 has fully finished: the
    /// panel fades (and blurs) away underneath — a plainer, non-particle sibling of
    /// `sequentialDissolve`.
    case sparkle = 0
    /// Pure scale-down + blur-out + fade of the entire panel as one snapshot — nothing
    /// animates separately from the shell.
    case vanish = 2
    /// Phase 1: the transcript text AND the waveform row both dissolve into dust.
    /// Phase 2, only once phase 1 has fully finished: the panel shell itself dissolves
    /// (and blurs) with the same dust language (particles masked to the rounded-rect,
    /// background fading underneath).
    case sequentialDissolve = 3
    /// Phase 1: the transcript TEXT and the WAVEFORM row both scatter into dust
    /// together (content shapes only — the panel fill never gets a particle
    /// treatment). Phase 2, starting strictly once phase 1 has fully finished (no
    /// overlap): the shell exits quietly with a smoother easeInOut blur+fade+scale.
    /// Default.
    case contentScatter = 4
    /// The ONLY effect: the dictated text scatters into dust (same InvisibleInkText
    /// language, thrown a bit further for more visible outward motion — see
    /// `InvisibleInkText.burstIntensity`). No waveform effect, no shell
    /// blur/fade/scale/particles of its own — once the text finishes, the shell just
    /// disappears with MiniWindowManager's plain default window-hide fade.
    case textScatterOnly = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .sparkle: return "V1"
        case .vanish: return "V3"
        case .sequentialDissolve: return "V4"
        case .contentScatter: return "V5"
        case .textScatterOnly: return "V6"
        }
    }

    var displayName: String {
        switch self {
        case .sparkle: return "Ink dissolve"
        case .vanish: return "Vanish"
        case .sequentialDissolve: return "Sequential dissolve"
        case .contentScatter: return "Content scatter"
        case .textScatterOnly: return "Text scatter only"
        }
    }

    /// True for effects that already animate the shell/panel to invisible themselves
    /// (a fade, blur+scale, or particle dissolve) — for those, RecorderUIManager skips
    /// MiniWindowManager's own window-hide fade so it doesn't visibly stack on top of
    /// an already-finished effect (see cancelRecordingAfterEffect). `textScatterOnly`
    /// never touches the shell at all, so the window's own fade is what makes it
    /// disappear — it must NOT be skipped there.
    var skipsWindowFadeOnCancel: Bool {
        self != .textScatterOnly
    }

    static let storageKey = "DismissEffectStyle"

    /// The removed V2 "poof" case's old raw value — never reused by a live case, kept
    /// only so `resolved(rawValue:)` can migrate an old selection to V4.
    private static let legacyPoofRawValue = 1

    /// Shared phase-1 timing for the staged (text-then-shell) effects — how long
    /// InvisibleInkText's glyph-sampled dust burst needs (worst case: its longest
    /// per-particle lifetime, ~0.5s, plus its small left-to-right sweep stagger,
    /// ~0.05s — see DustParticleLayer in InvisibleInkText.swift) before the shell's own
    /// exit may start.
    static let textDissolveDuration: TimeInterval = 0.55
    /// Phase-2 duration for `sequentialDissolve`'s shell burst. Trimmed slightly (was
    /// 0.48) so the total stays under the ~1s choreography budget now that
    /// textDissolveDuration grew to match the real glyph-dust timing.
    static let shellDissolveDuration: TimeInterval = 0.4
    /// Phase-2 duration for `sparkle`'s plain shell fade.
    static let sparkleShellFadeDuration: TimeInterval = 0.35

    /// `contentScatter` phase 1: how long the text + waveform particle scatter takes.
    /// Kept equal to `textDissolveDuration` so the two stay synced — the waveform's own
    /// dust (see Variant2View.cancelWaveformRow / BarDustView) runs on the same
    /// underlying DustParticleLayer timing as the text. Phase 2 (the shell exit) starts
    /// strictly at this duration — no overlap.
    static let contentScatterDuration: TimeInterval = 0.55
    /// Duration of `contentScatter`'s shell exit — a smoother, more fluid easeInOut
    /// blur+fade+scale than `vanish`'s snappier easeOut.
    static let contentScatterShellExitDuration: TimeInterval = 0.4

    /// Resolves a raw stored value to a live case. The Settings picker for choosing a
    /// dismiss effect was removed — V5 (`contentScatter`) is now pinned as the only
    /// effective style, so this ignores `raw` entirely and always returns
    /// `.contentScatter`. Kept as a function (rather than inlining `.contentScatter`
    /// at every call site) so a future picker could be reintroduced without touching
    /// the read sites — the other cases' implementations are still intact, just
    /// unreachable.
    static func resolved(rawValue _: Int) -> DismissEffectStyle {
        .contentScatter
    }

    /// One-time migration for the actual persisted UserDefaults value: without this,
    /// a picker bound directly to the raw Int (see SettingsView) would show no segment
    /// selected at all for an old V2 pick, since rawValue 1 no longer tags any case.
    /// Safe to call repeatedly — it's a no-op once migrated.
    static func migrateLegacyPoofSelectionIfNeeded() {
        guard UserDefaults.standard.object(forKey: storageKey) != nil,
              UserDefaults.standard.integer(forKey: storageKey) == legacyPoofRawValue else { return }
        UserDefaults.standard.set(DismissEffectStyle.sequentialDissolve.rawValue, forKey: storageKey)
    }

    static var stored: DismissEffectStyle {
        // No value ever saved (fresh install) → default to the new content-scatter
        // effect. `integer(forKey:)` alone can't distinguish "unset" from "explicitly
        // 0" (.sparkle), so check for presence first.
        guard UserDefaults.standard.object(forKey: storageKey) != nil else {
            return .contentScatter
        }
        return resolved(rawValue: UserDefaults.standard.integer(forKey: storageKey))
    }

    /// How long the effect needs to visually finish (includes a small safety buffer).
    /// RecorderUIManager sleeps this long before tearing the panel down, so the
    /// animation is never cut short.
    var duration: TimeInterval {
        switch self {
        case .sparkle:
            return Self.textDissolveDuration + Self.sparkleShellFadeDuration + 0.05
        case .vanish:
            return 0.45
        case .sequentialDissolve:
            return Self.textDissolveDuration + Self.shellDissolveDuration + 0.04
        case .contentScatter:
            return Self.contentScatterDuration + Self.contentScatterShellExitDuration + 0.03
        case .textScatterOnly:
            // Just the text-dissolve phase plus buffer — RecorderUIManager's sleep
            // covers only that; MiniWindowManager's own (unskipped) hide fade handles
            // however long the shell takes to disappear after this.
            return Self.textDissolveDuration + 0.05
        }
    }
}
