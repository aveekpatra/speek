import Foundation
enum ActionConnection: String { case localCodex, subscription, openRouter; static var preferred: Self { .openRouter } }
enum AgentDefaults { static func model(for: ActionConnection)->String {"model"}; static func reasoning(for: ActionConnection)->String? {"low"} }
enum ActionClientError: Error { case invalidResponse, requestFailed(String) }
enum ProposedActionKind: String, Codable { case openWebsite, searchWeb, openApp, remember, toolCall, answer, unsupported }
struct ProposedAction: Codable { var kind: ProposedActionKind; var title: String; var target: String; var response: String }
enum MCPValue: Codable { case string(String) }
struct RuntimeCall: Codable { var tool: String; var arguments: [String:MCPValue]; var json: String { tool }; init(tool:String,arguments:[String:MCPValue]) {self.tool=tool;self.arguments=arguments}; init(target:String)throws{self.tool=target;arguments=[:]} }
@MainActor final class ActionRuntime { static let shared = ActionRuntime(); var calls:[String]=[]; func context(for:String)->String{""}; func needsReview(_ call:RuntimeCall)throws->Bool{call.tool=="write"}; func execute(_ call:RuntimeCall,approved:Bool)async throws->String {assert(!approved);calls.append(call.tool);return "result https://example.com"} }
@MainActor final class OpenRouterActionClient { static let shared=OpenRouterActionClient(); var proposals:[ProposedAction]=[]; func propose(_ text:String,history:[String],contextNotes:String?,modelID:String?,reasoningEffort:String?)async throws->ProposedAction {proposals.removeFirst()} }
@MainActor enum CodexConnection { static func propose(_ text:String,history:[String],notes:String?,connection:ActionConnection,modelID:String?,reasoningEffort:String?)async throws->ProposedAction {throw ActionClientError.invalidResponse} }
