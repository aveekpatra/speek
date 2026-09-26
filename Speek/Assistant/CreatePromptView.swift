import SwiftUI
import AppKit

struct CreatePromptView: View {
    @StateObject private var session: CreatePromptSession
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var preview: PromptImagePreview?
    private let onUse: ((String) -> Void)?

    init(initialText: String, contextText: String = "", images: [Data] = [], connection: ActionConnection = .preferred, modelID: String? = nil, reasoningEffort: String? = nil, onUse: ((String) -> Void)? = nil) {
        _session = StateObject(wrappedValue: CreatePromptSession(initialText: initialText, contextText: contextText, images: images, connection: connection, modelID: modelID, reasoningEffort: reasoningEffort))
        self.onUse = onUse
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Create prompt").font(.system(size: 20, weight: .semibold))
                Text("Shape your request with the context and screenshots you captured.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            if !session.images.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(session.images.enumerated()), id: \.offset) { index, data in
                            PromptScreenshotTile(number: index + 1, data: data) {
                                preview = PromptImagePreview(number: index + 1, data: data)
                            }
                        }
                    }.padding(.vertical, 2)
                }.scrollIndicators(.hidden)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Prompt").font(.system(size: 13, weight: .medium))
                    Spacer()
                    if session.previousText != nil {
                        Button("Undo refinement") { session.restorePrevious() }.buttonStyle(.plain)
                            .font(.system(size: 11)).disabled(session.isRefining)
                    }
                }
                ZStack(alignment: .topLeading) {
                    if session.text.isEmpty {
                        Text("Describe the outcome, constraints, and what to use from the screenshots.")
                            .font(.system(size: 13)).foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $session.text).font(.system(size: 13)).scrollContentBackground(.hidden)
                        .accessibilityLabel("Prompt text").disabled(session.isRefining)
                }.padding(10).frame(minHeight: 190, maxHeight: .infinity)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08)))
            }
            VStack(alignment: .leading, spacing: 8) {
                TextField("Revision, optional. For example: make the requirements more precise", text: $session.revision)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12)).disabled(session.isRefining)
                    .accessibilityLabel("Revision instruction")
                    .onSubmit { session.refine() }
                HStack(spacing: 10) {
                    Text("Refine uses this chat's provider, model, and reasoning.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if session.isRefining {
                        ProgressView().controlSize(.small)
                        Button("Stop") { session.cancelRefinement() }.buttonStyle(SpeekActionButtonStyle())
                    } else {
                        Button("Refine") { session.refine() }.buttonStyle(SpeekActionButtonStyle()).disabled(!session.canUse)
                    }
                }
            }
            if let error = session.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if session.contextWasShortened {
                Text("The reference context contains its first 24,000 characters. All screenshots are retained.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: 10) {
                if !session.images.isEmpty {
                    Text("Copy includes text only. Images stay attached in Speek.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Cancel") { session.cancelRefinement(); dismiss() }
                    .buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.cancelAction)
                Button {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(session.text, forType: .string)
                } label: {
                    if copied { Label("Copied", systemImage: "checkmark.circle.fill") } else { Text("Copy text") }
                }.buttonStyle(SpeekActionButtonStyle()).disabled(!session.canUse)
                if let onUse {
                    Button("Use in chat") { onUse(session.text); dismiss() }
                        .buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction).disabled(!session.canUse)
                }
            }
        }.padding(24).frame(width: 650, height: session.images.isEmpty ? 570 : 680)
            .onChange(of: session.text) { _, _ in copied = false }
            .onDisappear { session.cancelRefinement() }
            .sheet(item: $preview) { image in
                VStack(alignment: .leading, spacing: 16) {
                    Text("Image \(image.number)").font(.system(size: 17, weight: .semibold))
                    if let decoded = NSImage(data: image.data) {
                        Image(nsImage: decoded).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else { Text("This image cannot be previewed.").font(.system(size: 13)).foregroundStyle(.secondary) }
                    HStack { Spacer(); Button("Done") { preview = nil }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction) }
                }.padding(24).frame(width: 560, height: 440)
            }
    }
}

private struct PromptImagePreview: Identifiable {
    var id: Int { number }
    let number: Int
    let data: Data
}

private struct PromptScreenshotTile: View {
    let number: Int
    let data: Data
    let onPreview: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            hovering = false
            onPreview()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 96, height: 66)
                        .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    Image(systemName: "photo").frame(width: 96, height: 66).foregroundStyle(.secondary)
                }
                Text("Image \(number)").font(.system(size: 11, weight: .medium)).foregroundStyle(.primary)
            }.padding(8).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityLabel("Preview image \(number)")
            .onHover { hovering = $0 }
            .popover(isPresented: $hovering, arrowEdge: .bottom) {
                if let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 380, maxHeight: 260).padding(8)
                }
            }
    }
}
