import SwiftUI
import AppKit
import CoreText

/// iMessage-style "Invisible Ink": the text is rendered as a field of tiny shimmering
/// particles (via CAEmitterLayer masked to the glyph shapes — the same technique Apple
/// uses) while idle. When `isDissolving` flips true, the solid text is hidden instantly
/// and a one-shot dust burst takes over — each particle starts at an exact glyph pixel
/// (sampled from the real letter shapes via CoreText, see `sampleGlyphDustPoints`
/// below), not spread across the text's bounding rectangle, so the letters themselves
/// visibly disintegrate.
struct InvisibleInkText: NSViewRepresentable {
    let text: String
    var fontSize: CGFloat = 13
    var isDissolving: Bool
    /// Scales the burst's outward velocity/drift. Defaults to 1.0 (identical to the
    /// original tuning) so every existing caller is unaffected; V6 "text scatter only"
    /// passes a higher value for more visible outward motion since it's the whole
    /// effect there, not one phase among several.
    var burstIntensity: CGFloat = 1.0

    func makeNSView(context: Context) -> InkView {
        let view = InkView()
        view.update(text: text, fontSize: fontSize)
        return view
    }

    func updateNSView(_ view: InkView, context: Context) {
        view.update(text: text, fontSize: fontSize)
        view.burstIntensity = burstIntensity
        view.setDissolving(isDissolving)
    }
}

final class InkView: NSView {
    private let visibleText = CATextLayer()   // solid readable words
    private let maskText = CATextLayer()       // glyph-shaped mask for the idle shimmer
    private let emitter = CAEmitterLayer()     // idle shimmer only — see setup()
    private let shimmerCell = CAEmitterCell()  // constant faint sparkle while idle
    private let dustLayer = DustParticleLayer() // one-shot glyph-sampled burst on dissolve

    private var currentText = ""
    private var currentFontSize: CGFloat = 13
    private var dissolving = false
    /// See `InvisibleInkText.burstIntensity`. Read only at the moment `setDissolving`
    /// starts a burst, so changing it mid-burst never retunes particles already in
    /// flight — only whichever value was current when a fresh dissolve began.
    var burstIntensity: CGFloat = 1.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var isFlipped: Bool { true }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false

        configureTextLayer(visibleText)
        configureTextLayer(maskText)

        // Idle shimmer only: particles live inside the glyph shapes via the mask copy,
        // and — unlike the old dissolve burst — this mask is never removed, so the
        // idle sparkle always stays glyph-shaped. The actual dissolve burst is a
        // completely separate mechanism (dustLayer, below) precisely because a shared
        // CAEmitterLayer's `emitterShape` only describes a geometric region (rectangle/
        // circle/line/point) to spawn *within* — there's no way to make it spawn only
        // from an arbitrary bitmap/glyph mask, only to CLIP what's already spawned. That
        // mismatch is what caused the old bug: removing the mask at burst time (to let
        // dust drift past the glyph edges) left particles spawning uniformly across the
        // whole rectangular `emitterSize`, not from the letters.
        emitter.emitterShape = .rectangle
        emitter.renderMode = .additive
        emitter.mask = maskText

        let dot = Self.particleImage()

        shimmerCell.contents = dot
        shimmerCell.birthRate = 70
        shimmerCell.lifetime = 1.1
        shimmerCell.lifetimeRange = 0.5
        shimmerCell.velocity = 2
        shimmerCell.velocityRange = 4
        shimmerCell.emissionRange = .pi * 2
        shimmerCell.scale = 0.16
        shimmerCell.scaleRange = 0.1
        shimmerCell.alphaSpeed = -0.9
        shimmerCell.color = NSColor.white.cgColor

        emitter.emitterCells = [shimmerCell]

        layer?.addSublayer(emitter)
        layer?.addSublayer(dustLayer)
        layer?.addSublayer(visibleText)
    }

    private func configureTextLayer(_ t: CATextLayer) {
        t.contentsScale = 2
        t.alignmentMode = .left
        t.isWrapped = true
        t.truncationMode = .none
        t.foregroundColor = NSColor.white.cgColor
    }

    func update(text: String, fontSize: CGFloat) {
        guard text != currentText || fontSize != currentFontSize else {
            layoutLayers()
            return
        }
        currentText = text
        currentFontSize = fontSize
        let font = NSFont.systemFont(ofSize: fontSize)
        for t in [visibleText, maskText] {
            t.string = text
            t.font = font
            t.fontSize = fontSize
        }
        layoutLayers()
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        let b = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        visibleText.frame = b
        maskText.frame = b
        emitter.frame = b
        emitter.emitterPosition = CGPoint(x: b.midX, y: b.midY)
        emitter.emitterSize = b.size
        dustLayer.frame = b
        CATransaction.commit()
    }

    func setDissolving(_ flag: Bool) {
        guard flag != dissolving else { return }
        dissolving = flag

        if flag {
            // Hide the solid words INSTANTLY (no fade) — the glyph-sampled dust burst
            // below is now the entire visual of the dissolve; a lingering block-level
            // fade on top of it would read as two competing effects instead of one.
            visibleText.removeAllAnimations()
            visibleText.opacity = 0
            shimmerCell.birthRate = 0

            let points = sampleGlyphDustPoints(
                text: currentText,
                font: NSFont.systemFont(ofSize: currentFontSize),
                bounds: bounds,
                stride: 2.5
            )
            dustLayer.burst(from: points, intensity: burstIntensity)
        } else {
            visibleText.opacity = 1
            shimmerCell.birthRate = 70
            dustLayer.reset()
        }
    }

    /// A soft round white dot used for every particle. Shared with `ShapeDissolveView`
    /// so the text dust and the panel-shell dust are visibly the same material.
    static func particleImage() -> CGImage? {
        let size = 12
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let center = CGPoint(x: size / 2, y: size / 2)
        let colors = [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) else { return nil }
        ctx.drawRadialGradient(
            gradient,
            startCenter: center, startRadius: 0,
            endCenter: center, endRadius: CGFloat(size) / 2,
            options: []
        )
        return ctx.makeImage()
    }
}

// MARK: - Glyph-sampled dust burst

/// Samples the ACTUAL rendered letter shapes (not the text's bounding rectangle) into a
/// grid of points, so a dust burst seeded from this list starts exactly where glyph ink
/// is. Uses CoreText's real glyph outlines (`CTFontCreatePathForGlyph`) rather than
/// rasterizing to a bitmap and thresholding alpha — same end result (points only where
/// a letter actually has ink), but avoids CALayer.render(in:)'s well-known "ignores the
/// layer's flipped-geometry setting" pitfall, which would otherwise risk an upside-down
/// or mirrored sample against a hand-rolled bitmap flip. `stride` matches the requested
/// "sample every Nth pixel"; a hard cap is applied by the caller (`DustParticleLayer.
/// burst`) so very long text doesn't spawn an unbounded number of particles.
private func sampleGlyphDustPoints(text: String, font: NSFont, bounds: CGRect, stride strideStep: CGFloat) -> [CGPoint] {
    guard !text.isEmpty, bounds.width > 1, bounds.height > 1 else { return [] }

    let attrString = NSAttributedString(string: text, attributes: [.font: font])
    let framesetter = CTFramesetterCreateWithAttributedString(attrString)
    let framePath = CGPath(rect: CGRect(origin: .zero, size: bounds.size), transform: nil)
    let ctFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attrString.length), framePath, nil)
    let ctFont = font as CTFont

    guard let lines = CTFrameGetLines(ctFrame) as? [CTLine], !lines.isEmpty else { return [] }
    var lineOrigins = [CGPoint](repeating: .zero, count: lines.count)
    CTFrameGetLineOrigins(ctFrame, CFRange(location: 0, length: 0), &lineOrigins)

    var points: [CGPoint] = []
    for (lineIndex, line) in lines.enumerated() {
        let lineOrigin = lineOrigins[lineIndex]
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { continue }

        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)

            for i in 0..<glyphCount {
                guard let glyphPath = CTFontCreatePathForGlyph(ctFont, glyphs[i], nil) else { continue }
                let box = glyphPath.boundingBoxOfPath
                guard box.width > 0.5, box.height > 0.5 else { continue }  // skip spaces etc.

                var y = box.minY
                while y <= box.maxY {
                    var x = box.minX
                    while x <= box.maxX {
                        if glyphPath.contains(CGPoint(x: x, y: y)) {
                            let framePoint = CGPoint(
                                x: lineOrigin.x + positions[i].x + x,
                                y: lineOrigin.y + positions[i].y + y
                            )
                            // CTFrame lays out text in Quartz's bottom-up space (origin
                            // at the bottom of `framePath`); flip into this view's
                            // top-left/y-down space to match `bounds`/`.frame` used
                            // everywhere else in this file.
                            points.append(CGPoint(x: framePoint.x, y: bounds.height - framePoint.y))
                        }
                        x += strideStep
                    }
                    y += strideStep
                }
            }
        }
    }
    return points
}

/// One-shot glyph-sampled dust burst: every particle starts exactly at a sampled glyph
/// point (see `sampleGlyphDustPoints`), then flies outward/upward with a bit of gravity
/// and fades out — kinematics are recomputed from elapsed time on every tick rather than
/// accumulated frame-to-frame, so there's no drift/rounding error over the effect's
/// short (~0.5s) life. A plain `CALayer` subclass with custom `draw(in:)` instead of a
/// SwiftUI `Canvas`, since this view is AppKit/NSViewRepresentable already (InkView) and
/// this keeps the whole dissolve mechanism in one coordinate space with no SwiftUI/
/// AppKit hosting boundary to cross.
private final class DustParticleLayer: CALayer {
    private struct Particle {
        let origin: CGPoint
        let velocity: CGVector   // pt/s
        let gravity: CGFloat     // pt/s², positive = falls in this view's y-down space
        let delay: TimeInterval
        let lifetime: TimeInterval
        let radius: CGFloat
    }

    /// Hard cap regardless of text length — long text increases the effective stride
    /// instead (evenly thinned) so density, and per-frame draw cost, stay bounded.
    private static let maxParticles = 900

    private var particles: [Particle] = []
    private var startTime: CFTimeInterval = 0
    private var tickTimer: Timer?

    override init() {
        super.init()
        contentsScale = 2
        needsDisplayOnBoundsChange = false
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func burst(from points: [CGPoint], intensity: CGFloat) {
        stopTicking()
        guard !points.isEmpty else {
            particles = []
            setNeedsDisplay()
            return
        }

        let sampled: [CGPoint]
        if points.count > Self.maxParticles {
            let keepEvery = Int((Double(points.count) / Double(Self.maxParticles)).rounded(.up))
            sampled = stride(from: 0, to: points.count, by: max(keepEvery, 1)).map { points[$0] }
        } else {
            sampled = points
        }

        particles = sampled.map { origin in
            // Outward direction with an upward bias (negative y, since this view's
            // space is y-down), jittered widely so it doesn't read as a uniform ring.
            let biasedAngle = -CGFloat.pi / 2 + CGFloat.random(in: -1.15...1.15)
            let speed = CGFloat.random(in: 22...54) * intensity
            let velocity = CGVector(dx: cos(biasedAngle) * speed, dy: sin(biasedAngle) * speed)
            // A small left-to-right sweep stagger, per the "letters near the start can
            // start a touch earlier" option — kept subtle (≤50ms) so it still reads as
            // one burst, not a wipe.
            let sweepDelay = Double(max(0, min(origin.x, 400)) / 400) * 0.05
            return Particle(
                origin: origin,
                velocity: velocity,
                gravity: CGFloat.random(in: 26...46),
                delay: sweepDelay + Double.random(in: 0...0.015),
                lifetime: Double.random(in: 0.44...0.56),
                radius: CGFloat.random(in: 0.9...1.8)
            )
        }

        startTime = CACurrentMediaTime()
        // `.common` mode so the burst keeps animating even during tracking/modal loops
        // (e.g. the user starts dragging the panel right as Escape fires) — a plain
        // `Timer.scheduledTimer` would silently pause in those run loop modes.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.current.add(timer, forMode: .common)
        tickTimer = timer
    }

    func reset() {
        stopTicking()
        particles = []
        setNeedsDisplay()
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        let elapsed = CACurrentMediaTime() - startTime
        if elapsed > 0.7 {
            stopTicking()
            particles = []
        }
        setNeedsDisplay()
    }

    /// Fraction of a particle's lifetime it stays at full brightness before fading. The
    /// color was already pure white — the "reads dark gray" complaint came from this
    /// curve being a straight 1→0 fade over the WHOLE lifetime (so at any given instant
    /// roughly half the visible dust sat under 50% alpha) combined with the tiny
    /// 0.7-1.5pt radius. Holding near-full alpha for most of the burst reads as clearly
    /// white dust — matching the transcript's own white text — with a short, sharp
    /// fade only at the very end instead of a slow dim the whole way through.
    private static let alphaHoldFraction: CGFloat = 0.55

    override func draw(in ctx: CGContext) {
        guard !particles.isEmpty else { return }
        let elapsed = CACurrentMediaTime() - startTime
        ctx.setFillColor(NSColor.white.cgColor)
        for p in particles {
            let t = elapsed - p.delay
            guard t >= 0, t <= p.lifetime else { continue }
            let tf = CGFloat(t)
            let x = p.origin.x + p.velocity.dx * tf
            let y = p.origin.y + p.velocity.dy * tf + 0.5 * p.gravity * tf * tf
            let progress = CGFloat(t / p.lifetime)
            let alpha: CGFloat = progress < Self.alphaHoldFraction
                ? 1
                : 1 - (progress - Self.alphaHoldFraction) / (1 - Self.alphaHoldFraction)
            ctx.setAlpha(alpha)
            ctx.fillEllipse(in: CGRect(x: x - p.radius, y: y - p.radius, width: p.radius * 2, height: p.radius * 2))
        }
    }
}

// MARK: - Waveform-bar dust burst (sparkle / sequentialDissolve / contentScatter)

/// Same glyph-dust language as `InvisibleInkText`, applied to the calm resting
/// waveform (`StaticVisualizer`, shown in `Variant2View.cancelWaveformRow`) instead of
/// letters — reuses the identical `DustParticleLayer` motion/lifetime/color, just
/// seeded from bar-shaped points instead of glyph-shaped ones, so text and waveform
/// visibly dissolve as one consistent material rather than two different tricks. Used
/// by every staged-text-dissolve effect (see `Variant2View.showsWaveformDust`) except
/// `textScatterOnly`, which is deliberately text-only.
struct BarDustView: NSViewRepresentable {
    var isDissolving: Bool
    var intensity: CGFloat = 1

    func makeNSView(context: Context) -> BarDustNSView {
        BarDustNSView()
    }

    func updateNSView(_ view: BarDustNSView, context: Context) {
        view.setDissolving(isDissolving, intensity: intensity)
    }
}

final class BarDustNSView: NSView {
    private let dustLayer = DustParticleLayer()
    private var dissolving = false

    // Mirrors StaticVisualizer's own bar geometry exactly (see AudioVisualizerView.
    // swift) so the dust originates from the same bars the user was just looking at —
    // duplicated as literal constants rather than reading them from StaticVisualizer
    // (its fields are private, and that file wasn't otherwise part of this change).
    private static let barCount = 15
    private static let barWidth: CGFloat = 3
    private static let barHeight: CGFloat = 4
    private static let barSpacing: CGFloat = 2
    private static let sampleStride: CGFloat = 1.1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var isFlipped: Bool { true }

    private func setup() {
        wantsLayer = true
        layer?.addSublayer(dustLayer)
    }

    override func layout() {
        super.layout()
        dustLayer.frame = bounds
    }

    func setDissolving(_ flag: Bool, intensity: CGFloat) {
        guard flag != dissolving else { return }
        dissolving = flag
        if flag {
            dustLayer.burst(from: sampleBarPoints(), intensity: intensity)
        } else {
            dustLayer.reset()
        }
    }

    /// A small grid of points per bar (its width × height at `sampleStride`), centered
    /// exactly the way `StaticVisualizer`'s `HStack` lays its bars out.
    private func sampleBarPoints() -> [CGPoint] {
        let b = bounds
        guard b.width > 1, b.height > 1 else { return [] }

        let total = CGFloat(Self.barCount) * Self.barWidth + CGFloat(Self.barCount - 1) * Self.barSpacing
        var barOriginX = (b.width - total) / 2
        let barOriginY = (b.height - Self.barHeight) / 2

        var points: [CGPoint] = []
        for _ in 0..<Self.barCount {
            var y = barOriginY
            while y <= barOriginY + Self.barHeight {
                var x = barOriginX
                while x <= barOriginX + Self.barWidth {
                    points.append(CGPoint(x: x, y: y))
                    x += Self.sampleStride
                }
                y += Self.sampleStride
            }
            barOriginX += Self.barWidth + Self.barSpacing
        }
        return points
    }
}

// MARK: - Panel-shell dissolve (V4 phase 2)

/// Dissolves an arbitrary rounded-rect *shape* — the panel shell, not glyphs — into the
/// same dust-particle language as `InvisibleInkText`, so a dismiss effect can stage
/// "text dissolves, then the container dissolves" as one continuous visual dialect
/// instead of two different tricks. Purely a particle overlay: the shell's own
/// background/border fade is driven by the caller's `.opacity`, this view only adds the
/// dust masked to the same rounded-rect the panel already uses.
struct ShapeDissolveView: NSViewRepresentable {
    var cornerRadius: CGFloat
    var isDissolving: Bool

    func makeNSView(context: Context) -> ShapeDissolveNSView {
        let view = ShapeDissolveNSView()
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: ShapeDissolveNSView, context: Context) {
        view.cornerRadius = cornerRadius
        view.setDissolving(isDissolving)
    }
}

final class ShapeDissolveNSView: NSView {
    private let maskShape = CAShapeLayer()  // rounded-rect mask so dust stays confined to the pill's silhouette
    private let emitter = CAEmitterLayer()
    private let burstCell = CAEmitterCell()

    var cornerRadius: CGFloat = 18 {
        didSet { layoutLayers() }
    }
    private var dissolving = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var isFlipped: Bool { true }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false

        maskShape.fillColor = NSColor.white.cgColor

        emitter.emitterShape = .rectangle
        emitter.renderMode = .additive
        emitter.mask = maskShape

        burstCell.contents = InkView.particleImage()
        burstCell.birthRate = 0
        burstCell.lifetime = 1.0
        burstCell.lifetimeRange = 0.4
        burstCell.velocity = 34
        burstCell.velocityRange = 26
        burstCell.yAcceleration = -12
        burstCell.emissionRange = .pi * 2
        burstCell.scale = 0.2
        burstCell.scaleRange = 0.14
        burstCell.alphaSpeed = -0.8
        burstCell.color = NSColor.white.cgColor
        emitter.emitterCells = [burstCell]

        layer?.addSublayer(emitter)
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        let b = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskShape.frame = b
        maskShape.path = CGPath(roundedRect: b, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        emitter.frame = b
        emitter.emitterPosition = CGPoint(x: b.midX, y: b.midY)
        emitter.emitterSize = b.size
        CATransaction.commit()
    }

    func setDissolving(_ flag: Bool) {
        guard flag != dissolving else { return }
        dissolving = flag

        if flag {
            burstCell.birthRate = 900
            // Stop spawning shortly after the burst so the dust can fully disperse
            // instead of trailing new particles for the whole phase.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                self?.burstCell.birthRate = 0
            }
        } else {
            burstCell.birthRate = 0
        }
    }
}
