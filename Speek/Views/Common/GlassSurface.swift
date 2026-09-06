import SwiftUI
import AppKit

/// Shared "Liquid Glass" surface treatment for the app's floating chrome.
///
/// On macOS 26+ this uses Apple's real Liquid Glass material (`.glassEffect`); below
/// macOS 26 it falls back to whatever background the surface already used, so there is
/// no regression on older systems. Kept deliberately restrained — glass belongs on
/// surfaces that float over arbitrary content (the recorder pills), not on dense text
/// or charts that need a flat, readable background.
enum GlassSurface {
    /// Strong dark tint used by chrome that wants to read as near-black. Currently only
    /// the Settings preview card background (the floating recorder pills themselves
    /// gave up on glass entirely and use a plain solid-black background instead — see
    /// Variant2View/Variant16View — since even this tint still read as grayish there).
    static let darkChromeTint = Color.black.opacity(0.85)

    /// Faint accent tint for small interactive accent-colored chips (e.g. the
    /// "selected language" chips in Settings). The chip's text and border are
    /// accent-colored, so the glass keeps a whisper of accent (mirroring the old
    /// `AppTheme.Accent.fillSubtle` wash at 0.10) to preserve the chip's accent
    /// identity without muddying that accent-colored text.
    static let settingsAccentChipTint = AppTheme.Accent.primary.opacity(0.14)

    /// Tint for accent-colored (blue) primary buttons — e.g. "Download" — so they keep
    /// reading as a prominent blue action while the glass adds refraction on macOS 26+.
    static let accentButtonTint = AppTheme.Accent.primary.opacity(0.6)
}

extension View {
    /// Applies native Liquid Glass clipped to `shape` on macOS 26+, else draws the
    /// supplied `fallback` background (the surface's pre-existing look) so nothing
    /// regresses below macOS 26.
    /// - Parameters:
    ///   - shape: the glass silhouette (e.g. `Capsule()` or a `RoundedRectangle`).
    ///   - tint: optional glass tint. Leave `nil` for a neutral, adaptive glass on
    ///     light panels.
    ///   - fallback: the background used below macOS 26 (the current treatment).
    @ViewBuilder
    func glassSurface<S: Shape, Fallback: View>(
        in shape: S,
        tint: Color? = nil,
        @ViewBuilder fallback: () -> Fallback
    ) -> some View {
        if #available(macOS 26.0, *) {
            let glass: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
            glassEffect(glass, in: shape)
        } else {
            background(fallback())
        }
    }

    /// Rounded-rectangle convenience for `glassSurface(in:tint:fallback:)`.
    /// Prefer a radius token (`AppTheme.Radius.card` / `.control`) or the surface's own
    /// radius.
    func glassSurface<Fallback: View>(
        cornerRadius: CGFloat,
        tint: Color? = nil,
        @ViewBuilder fallback: () -> Fallback
    ) -> some View {
        glassSurface(
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint,
            fallback: fallback
        )
    }

    /// Native glass button on macOS 26+, else the supplied fallback style. Only worth
    /// using on plain, unstyled controls — surfaces with bespoke button chrome should
    /// keep their own style rather than layering a second glass capsule behind it.
    @ViewBuilder
    func glassButtonStyle<Fallback: PrimitiveButtonStyle>(fallback: Fallback) -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(fallback)
        }
    }
}
