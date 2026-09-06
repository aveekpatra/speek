import Testing
import SwiftUI
import AppKit
@testable import Speek

@MainActor
struct WidgetSnapshotTests {

    // Mirrors Variant2View's pill layout but renders the text directly instead of
    // inside a ScrollView, because ImageRenderer cannot rasterize ScrollView content.
    // For text within the cap this is pixel-identical to the live widget.
    @ViewBuilder
    private func previewPill(committed: String, partial: String, showToggle: Bool = true) -> some View {
        let needsSpace = !committed.isEmpty
            && !(committed.last?.isWhitespace ?? true)
            && !(partial.first?.isWhitespace ?? true)
            && !(partial.first.map { ".,!?;:".contains($0) } ?? false)
        let tail = needsSpace ? " " + partial : partial

        VStack(spacing: 0) {
            (Text(committed).foregroundColor(.white)
                + Text(tail).foregroundColor(.white.opacity(0.45)))
                .font(.system(size: 13))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 6)

            HStack(spacing: 0) {
                Spacer(minLength: 16)
                RecorderStatusDisplay(currentState: .recording,
                                      audioMeter: AudioMeter(averagePower: 0.6, peakPower: 0.8))
                    .frame(height: 40)
                Spacer(minLength: 16)
            }
        }
        .frame(width: 384)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6))
        .overlay(alignment: .bottomTrailing) {
            if showToggle {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .padding(.trailing, 12)
                    .padding(.bottom, 11)
            }
        }
        .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: 6)
    }

    // Collapsed (voice-only) pill with the expand icon centered on the right edge.
    @ViewBuilder
    private func collapsedPreviewPill() -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 8)
            RecorderStatusDisplay(currentState: .recording,
                                  audioMeter: AudioMeter(averagePower: 0.6, peakPower: 0.8))
                .frame(height: 40)
            Spacer(minLength: 8)
        }
        .frame(width: 138)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6))
        .overlay(alignment: .trailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .padding(.trailing, 8)
        }
        .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: 6)
    }

    private func renderPreview(committed: String, partial: String, to path: String) throws {
        let view = previewPill(committed: committed, partial: partial)
            .padding(40)
            .background(Color(white: 0.16))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "snapshot", code: 1)
        }
        try png.write(to: URL(fileURLWithPath: path))
    }

    private func render(_ context: WidgetVariantContext, to path: String) throws {
        let view = Variant2View(context: context)
            .frame(width: 480, height: 360)
            .background(Color(white: 0.16))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "snapshot", code: 1)
        }
        try png.write(to: URL(fileURLWithPath: path))
    }

    @Test func renderShort() throws {
        try render(
            WidgetVariantContext(
                committed: "text, který do toho jakoby píšeš. A potom jsem si všimnul, že tam je ještě jeden takovej b",
                partial: "ug",
                audioMeter: AudioMeter(averagePower: 0.6, peakPower: 0.8),
                recordingState: .recording
            ),
            to: "/tmp/widget-v2-short.png"
        )
    }

    @Test func renderText() throws {
        try renderPreview(
            committed: "text, který do toho jakoby píšeš. A potom jsem si všimnul, že tam je ještě jeden takovej b",
            partial: "ug",
            to: "/tmp/widget-v2-text.png"
        )
    }

    @Test func renderTwoRows() throws {
        let view = previewPill(
            committed: "Tohle je krátký text na dva řádky, jak vypadá výchozí stav",
            partial: " widgetu"
        )
        .padding(40)
        .background(Color(white: 0.16))
        try writePNG(view, to: "/tmp/widget-v2-tworows.png")
    }

    // Mirrors Variant2View.cancelContent's static (first-Escape) look.
    @ViewBuilder
    private func cancelConfirmPill() -> some View {
        ZStack {
            (Text("text, který jsem právě nadiktoval a teď ho ruším")
                .foregroundColor(.white))
                .font(.system(size: 13))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .blur(radius: 16)
                .opacity(0.4)

            (Text("Esc").foregroundColor(.white).fontWeight(.semibold)
                + Text(" again to cancel").foregroundColor(.white.opacity(0.45)))
                .font(.system(size: 13))

            Text("V1")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(8)
        }
        .frame(width: 384, height: 100)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6))
        .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: 6)
    }

    @Test func renderWaveformPills() throws {
        let meter = AudioMeter(averagePower: 0.7, peakPower: 0.85)
        let stack = VStack(spacing: 14) {
            ForEach(0..<WaveformStyleView.styleCount, id: \.self) { i in
                HStack(spacing: 14) {
                    Text("\(i)").font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.5)).frame(width: 18)
                    HStack(spacing: 0) {
                        Spacer(minLength: 16)
                        WaveformStyleView(style: i, audioMeter: meter, isActive: true)
                            .frame(height: 40)
                        Spacer(minLength: 16)
                    }
                    .frame(width: 280)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6))
                }
            }
        }
        .padding(28)
        .background(Color(white: 0.16))
        try writePNG(stack, to: "/tmp/widget-v2-wave-pills.png")
    }

    @Test func renderWaveformStyles() throws {
        let meter = AudioMeter(averagePower: 0.7, peakPower: 0.85)
        let grid = VStack(spacing: 10) {
            ForEach(0..<WaveformStyleView.styleCount, id: \.self) { i in
                HStack(spacing: 12) {
                    Text("\(i)").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.5)).frame(width: 16)
                    WaveformStyleView(style: i, audioMeter: meter, isActive: true)
                        .frame(width: 132, height: 28)
                }
            }
        }
        .padding(20)
        .background(Color.black)
        try writePNG(grid, to: "/tmp/widget-v2-waveforms.png")
    }

    @Test func renderCancelConfirm() throws {
        let view = cancelConfirmPill()
            .padding(40)
            .background(Color(white: 0.16))
        try writePNG(view, to: "/tmp/widget-v2-cancel.png")
    }

    @Test func renderCollapsed() throws {
        let view = collapsedPreviewPill()
            .padding(40)
            .background(Color(white: 0.16))
        try writePNG(view, to: "/tmp/widget-v2-collapsed.png")
    }

    private func writePNG(_ view: some View, to path: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "snapshot", code: 1)
        }
        try png.write(to: URL(fileURLWithPath: path))
    }

    @Test func renderLong() throws {
        let long = (1...22).map { "Tohle je řádek číslo \($0) toho dlouhého textu." }.joined(separator: " ")
        try render(
            WidgetVariantContext(
                committed: long + " a tady končí to potvrzený slovo b",
                partial: "ug",
                audioMeter: AudioMeter(averagePower: 0.5, peakPower: 0.7),
                recordingState: .recording
            ),
            to: "/tmp/widget-v2-long.png"
        )
    }
}
