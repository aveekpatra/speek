import SwiftUI

/// Kept outside the transcript's scroll view so permission requests stay visible.
struct ComputerUseApprovalView: View {
    @ObservedObject private var computer = CodexComputerUse.shared
    @ObservedObject private var tasks = ComputerTaskManager.shared
    @State private var answer = ""

    var body: some View {
        if let request = computer.approval {
            VStack(alignment: .leading, spacing: 14) {
                Label(request.title, systemImage: "hand.raised")
                    .font(.system(size: 14, weight: .semibold))
                if let job = tasks.currentJob {
                    Text(job.request).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
                ScrollView {
                    Text(request.message).font(.system(size: 13))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 110)
                if request.needsInput {
                    TextField("Your answer", text: $answer).textFieldStyle(.roundedBorder)
                        .onSubmit { submit(request) }
                }
                HStack(spacing: 10) {
                    Text(request.coversTask ? "Covers routine actions for this task." : "Nothing is approved until you respond.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Cancel") { computer.answerApproval(id: request.id, answer: nil) }
                        .buttonStyle(SpeekActionButtonStyle())
                    Button(request.needsInput ? "Continue" : (request.coversTask ? "Allow this task" : "Allow once")) { submit(request) }
                        .buttonStyle(SpeekActionButtonStyle())
                        .disabled(request.needsInput && answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(18)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.09)))
            .frame(maxWidth: 720).padding(.horizontal, 38).padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .onChange(of: request.id) { _, _ in answer = "" }
        }
    }
    private func submit(_ request: ComputerUseApproval) {
        let text = request.needsInput ? answer.trimmingCharacters(in: .whitespacesAndNewlines) : (request.coversTask ? "Allow this task" : "Allow once")
        guard !text.isEmpty else { return }
        computer.answerApproval(id: request.id, answer: text)
        answer = ""
    }
}

struct ComputerTaskListView: View {
    @ObservedObject private var tasks = ComputerTaskManager.shared

    var body: some View {
        if !tasks.jobs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Computer tasks").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(tasks.jobs) { job in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "desktopcomputer").frame(width: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(job.request).font(.system(size: 13)).lineLimit(2)
                                Text(job.progress).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if job.status == .queued || job.status == .running {
                                Button("Cancel") { tasks.cancel(job.id) }.buttonStyle(SpeekActionButtonStyle())
                            } else if job.status == .interrupted {
                                Button("Retry") { AssistantController.shared.retryComputerTask(job) }.buttonStyle(SpeekActionButtonStyle())
                                Button { tasks.dismiss(job.id) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain).help("Dismiss task")
                            } else {
                                Button { tasks.dismiss(job.id) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain).help("Dismiss task")
                            }
                        }
                        if let result = job.result {
                            DisclosureGroup("Result") {
                                Text(result).font(.system(size: 13)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                            }.font(.system(size: 12))
                        }
                    }.padding(14)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}
