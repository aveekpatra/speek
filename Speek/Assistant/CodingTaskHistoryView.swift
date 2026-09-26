import SwiftUI
import AppKit

struct CodingTaskHistoryView: View {
    @ObservedObject private var coding = CodingTaskManager.shared
    @State private var continuingCoding: CodingTaskJob?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Coding tasks").font(.system(size: 25, weight: .semibold))
                    Text("Your coding requests, progress, and results.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                if coding.jobs.isEmpty {
                    empty("No coding tasks yet", detail: "Coding requests appear here when started from a chat or shortcut.", symbol: "terminal")
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(coding.jobs) { job in codingCard(job) }
                    }
                }
                if let storageError = coding.storageError { errorLabel(storageError) }
            }.frame(maxWidth: 880, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }
        .sheet(item: $continuingCoding) { job in CodingTaskReviewView(resuming: job) }
    }

    private func codingCard(_ job: CodingTaskJob) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: job.status == .completed ? "checkmark.circle.fill" : "terminal")
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.request.split(separator: "\n").first.map(String.init) ?? "Coding request")
                        .font(.system(size: 13, weight: .medium)).lineLimit(2)
                    Text("\(job.engine.title) - \(job.status.rawValue.capitalized)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(job.updatedAt, style: .relative).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(job.directory).font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            if job.status == .running, let latest = job.progress.last {
                Text(latest).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
            }
            if let failure = job.error { errorLabel(failure) }
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(job.request).font(.system(size: 13)).textSelection(.enabled)
                    if let result = job.result {
                        Divider()
                        Text(result).font(.system(size: 13)).textSelection(.enabled)
                    }
                    if !job.progress.isEmpty {
                        DisclosureGroup("Progress") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(job.progress.enumerated()), id: \.offset) { _, text in
                                    Text(text).font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        }.font(.system(size: 11))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }.font(.system(size: 11))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { Spacer(minLength: 0); codingActions(job) }
                VStack(alignment: .trailing, spacing: 8) { codingActions(job) }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }.padding(20).settingsSurface()
    }

    @ViewBuilder private func codingActions(_ job: CodingTaskJob) -> some View {
        Button("Open project") { NSWorkspace.shared.open(URL(fileURLWithPath: job.directory)) }
            .buttonStyle(SpeekActionButtonStyle())
        if [.running, .queued].contains(job.status) {
            Button("Cancel") { coding.cancel(job.id) }.buttonStyle(SpeekActionButtonStyle())
        } else {
            if job.sessionID != nil {
                Button("Continue") { continuingCoding = job }.buttonStyle(SpeekActionButtonStyle())
            }
            Button("Remove", role: .destructive) { coding.remove(job.id) }.buttonStyle(SpeekActionButtonStyle())
        }
    }

    private func empty(_ title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).settingsSurface()
    }
    private func errorLabel(_ text: String) -> some View { Text(text).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
}
