import Foundation

enum OnlineTextTone: String, CaseIterable, Identifiable {
    case casual, semiCasual = "semi-casual", semiFormal = "semi-formal", formal

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .casual: return "Casual"
        case .semiCasual: return "Semi-casual"
        case .semiFormal: return "Semi-formal"
        case .formal: return "Formal"
        }
    }
}

enum OnlineTextStructure: String, CaseIterable, Identifiable {
    case prose, lists

    var id: String { rawValue }
    var displayName: String { self == .prose ? "Prose" : "Lists" }
}
