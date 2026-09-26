import Foundation
import SwiftUI
enum ActionConnection:String,Codable {case localCodex,subscription,openRouter}
enum AgentDefaults { static func model(for:ActionConnection)->String {"gpt-6-luna"} }
enum CodexJobError:Error {case notInstalled,failed(String)}
enum CodexConnection {static var binary:String? {"/opt/homebrew/bin/codex"};static func environment(for:ActionConnection)throws->[String:String]{[:]} }
struct AssistantModelOption:Identifiable {var id:String;var name:String;var efforts:[String]}
enum AssistantModelCatalog {static func load(connection:ActionConnection)async throws->[AssistantModelOption]{[]} }
