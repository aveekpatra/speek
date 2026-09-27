import SwiftUI

struct BackgroundTaskNotice: Identifiable {
    let id = UUID()
    let request: String
    let result: String
    let sourceThreadID: UUID?
    let succeeded: Bool
    let date = Date()
    /// Asked out loud: the result is announced out loud.
    var spoken = false
}

struct BackgroundTaskNoticeView: View {
    @ObservedObject var controller: AssistantController

    var body: some View {
        if let notice = controller.taskNotices.first {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: notice.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    Text(notice.succeeded ? "Task complete" : "Task needs attention")
                        .font(.system(size: 12, weight: .semibold))
                    if controller.taskNotices.count > 1 {
                        Text("+\(controller.taskNotices.count - 1)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button("View result") { controller.openTaskNotice(notice) }
                        .buttonStyle(.plain).font(.system(size: 12))
                        .disabled(controller.busy || controller.recording)
                    Button { controller.dismissTaskNotice(notice.id) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).help("Dismiss completion")
                }
                Text(notice.request).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Text(notice.result).font(.system(size: 12)).lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
