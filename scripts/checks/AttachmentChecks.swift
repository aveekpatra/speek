import Foundation
import AppKit
import PDFKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

@main struct AttachmentChecks {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("speek-attachment-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = folder.appendingPathComponent("notes.txt")
        try "A useful note".write(to: text, atomically: true, encoding: .utf8)
        let note = try ComposerAttachmentStore.read(url: text)
        precondition(note.extractedText == "A useful note" && note.kind == .text)
        let long = folder.appendingPathComponent("long.txt")
        try String(repeating: "a", count: 30_000).write(to: long, atomically: true, encoding: .utf8)
        let excerpt = try ComposerAttachmentStore.read(url: long)
        precondition(excerpt.isTruncated && excerpt.extractedText.count == 24_000)
        let imageFile = folder.appendingPathComponent("image.png")
        let context = CGContext(data: nil, width: 3000, height: 1200, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1200))
        let destination = CGImageDestinationCreateWithURL(imageFile as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        let image = try ComposerAttachmentStore.read(url: imageFile)
        let decoded = CGImageSourceCreateWithData(image.imageData! as CFData, nil)!
        let resized = CGImageSourceCreateImageAtIndex(decoded, 0, nil)!
        precondition(resized.width == 2048 && image.kind == .image)
        let pdfFile = folder.appendingPathComponent("document.pdf")
        var box = CGRect(x: 0, y: 0, width: 400, height: 600)
        let pdfContext = CGContext(pdfFile as CFURL, mediaBox: &box, nil)!
        pdfContext.beginPDFPage(nil)
        pdfContext.textPosition = CGPoint(x: 20, y: 500)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Readable PDF content", attributes: [.font: NSFont.systemFont(ofSize: 14)]))
        CTLineDraw(line, pdfContext)
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        let pdf = try ComposerAttachmentStore.read(url: pdfFile)
        precondition(pdf.extractedText.contains("Readable PDF content") && pdf.kind == .document)
        let large = folder.appendingPathComponent("oversized.txt")
        try Data(repeating: 65, count: ComposerAttachmentStore.fileLimit + 1).write(to: large)
        do { _ = try ComposerAttachmentStore.read(url: large); fatalError("Oversized file accepted") } catch {}
        do { _ = try ComposerAttachmentStore.read(url: URL(string: "https://example.com/test.txt")!); fatalError("Remote URL accepted") } catch {}
        let store = ComposerAttachmentStore()
        store.add(urls: [text, imageFile, pdfFile])
        while store.isImporting { try await Task.sleep(nanoseconds: 10_000_000) }
        precondition(store.attachments.count == 3 && store.images.count == 1 && store.textContext.contains("Readable PDF"))
        store.remove(id: store.attachments[0].id)
        precondition(store.attachments.count == 2)
        store.clear()
        precondition(store.attachments.isEmpty && store.images.isEmpty && store.textContext.isEmpty)
        print("PASS: text/PDF extraction, visible truncation, bounded image resize, file limits, remote URL rejection, import/remove/clear")
    }
}
