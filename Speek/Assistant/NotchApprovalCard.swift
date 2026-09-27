import SwiftUI

/// Permission requests answered from the notch, so the main window never has to open.
/// Computer-use questions come first because a running task is waiting on them.
struct NotchApprovalCard: View {
    @ObservedObject var controller: AssistantController
    @ObservedObject private var computer = CodexComputerUse.shared
    @ObservedObject private var tasks = ComputerTaskManager.shared
    @State private var answer = ""

    var body: some View {
        if let request = computer.approval {
            computerCard(request)
        } else if let proposal = controller.proposal, let call = try? RuntimeCall(target: proposal.target) {
            if let rich = RichCard.detect(call) {
                RichApprovalCard(card: rich, call: call, source: ActionRuntime.shared.source(of: call.tool), controller: controller)
                    .id(proposal.target)
            } else {
                toolCard(proposal, call: call)
            }
        }
    }

    // MARK: Tool call

    private func toolCard(_ proposal: ProposedAction, call: RuntimeCall) -> some View {
        let tool = ActionRuntime.shared.tools.first { $0.id == call.tool }
        return card(title: tool?.title ?? proposal.title, subtitle: proposal.title == tool?.title ? nil : proposal.title,
                    lines: Self.argumentLines(call)) {
            Button("Edit...") { controller.reviewInMainWindow() }.buttonStyle(.plain).font(.system(size: 12))
                .disabled(controller.busy)
            Spacer(minLength: 8)
            Button("Deny") { controller.cancelProposal() }.buttonStyle(SpeekActionButtonStyle())
            Button("Always Allow") {
                ToolPolicyStore.shared.set(.allow, for: call.tool)
                controller.runProposal()
            }.buttonStyle(SpeekActionButtonStyle()).help("Run now and stop asking for " + (tool?.title ?? "this tool"))
            Button("Allow") { controller.runProposal() }.buttonStyle(SpeekActionButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }

    static func argumentLines(_ call: RuntimeCall) -> [String] {
        call.arguments.keys.sorted().prefix(4).map { key in
            let value: String
            switch call.arguments[key] {
            case .string(let text)?: value = text
            case let other?: value = other.jsonString
            case nil: value = ""
            }
            let label = key.replacingOccurrences(of: "_", with: " ").capitalized
            return label + ": " + value.replacingOccurrences(of: "\n", with: " ")
        }
    }

    // MARK: Computer use

    private func computerCard(_ request: ComputerUseApproval) -> some View {
        let lines = request.message.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return card(title: request.title, subtitle: tasks.currentJob?.request, lines: Array(lines.prefix(4))) {
            if request.needsInput {
                TextField("Your answer", text: $answer).textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 8).frame(height: 28)
                    .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit { submit(request) }
                Button("Cancel") { computer.answerApproval(id: request.id, answer: nil) }.buttonStyle(SpeekActionButtonStyle())
                Button("Continue") { submit(request) }.buttonStyle(SpeekActionButtonStyle())
                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Spacer(minLength: 8)
                Button("Deny") { computer.answerApproval(id: request.id, answer: nil) }.buttonStyle(SpeekActionButtonStyle())
                if request.coversTask {
                    Button("Always Allow") {
                        ToolPolicyStore.shared.set(.allow, for: ToolPolicyStore.computerUseID)
                        computer.answerApproval(id: request.id, answer: "Allow this task")
                    }.buttonStyle(SpeekActionButtonStyle()).help("Allow routine computer actions without asking")
                }
                Button(request.coversTask ? "Allow Task" : "Allow") {
                    computer.answerApproval(id: request.id, answer: request.coversTask ? "Allow this task" : "Allow once")
                }.buttonStyle(SpeekActionButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .onChange(of: request.id) { _, _ in answer = "" }
    }

    private func submit(_ request: ComputerUseApproval) {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        computer.answerApproval(id: request.id, answer: text)
        answer = ""
    }

    // MARK: Layout

    private func card<Actions: View>(title: String, subtitle: String?, lines: [String], @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill").font(.system(size: 12))
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 12)).lineLimit(1).truncationMode(.tail).textSelection(.enabled)
                    }
                }
            }
            HStack(spacing: 8) { actions() }.padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Height the notch reserves for the card, matching the layout above.
    @MainActor static func height(for controller: AssistantController) -> Int {
        if let request = CodexComputerUse.shared.approval {
            let lines = min(4, request.message.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count)
            return 88 + lines * 16 + (ComputerTaskManager.shared.currentJob == nil ? 0 : 16)
        }
        if let proposal = controller.proposal, let call = try? RuntimeCall(target: proposal.target) {
            if let rich = RichCard.detect(call) { return RichApprovalCard.height(for: rich) }
            return 104 + min(4, call.arguments.count) * 16
        }
        return 0
    }
}
