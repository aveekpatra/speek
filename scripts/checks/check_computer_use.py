#!/usr/bin/env python3
"""Exercise the production JSONL transport with an isolated fake Codex server."""
import pathlib, subprocess, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[2]
STUB = '''import Foundation
import AppKit
import Combine
enum ActionClientError: Error { case requestFailed(String) }
enum CodexJobError: Error { case notInstalled }
enum ActionConnection { case localCodex }
enum AgentDefaults { static func model(for connection: ActionConnection) -> String { "test-model" } }
enum ActionRole: String { case user, assistant }
struct ActionMessage { let role: ActionRole; let text: String }
enum ToolPolicy { case ask, allow, never }
@MainActor final class ToolPolicyStore {
 static let shared = ToolPolicyStore(); static let computerUseID = "computer.use"
 var computerUse: ToolPolicy = .ask
 func policy(for toolID: String, changesData: Bool) -> ToolPolicy { computerUse }
}
enum CodexConnection {
 static var binary: String? { CommandLine.arguments[1] }
 static func environment(for connection: ActionConnection) throws -> [String:String] { ProcessInfo.processInfo.environment }
}
'''
MAIN = '''import Foundation
@main struct Checks {
 @MainActor static func main() async throws {
  let chrome = BrowserGuard(request: "Open LinkedIn in this browser and go to my company page", defaultBrowser: "Google Chrome")
  precondition(chrome.allowed == ["Chrome"], "default browser should be the only one allowed")
  precondition(chrome.violation(in: #"{"arguments":"await cua.getApp(\"Safari\")"}"#) == "Safari", "other browser not blocked")
  precondition(chrome.violation(in: #"open -a "Google Chrome" https://linkedin.com"#) == nil, "allowed browser blocked")
  precondition(chrome.violation(in: "searching the archive for operation notes") == nil, "false positive on ordinary words")
  let ego = BrowserGuard(request: "Use Ego browser to check my inbox", defaultBrowser: "Safari")
  precondition(ego.allowed == ["Ego"] && ego.violation(in: #"cua.getApp(\"Safari\")"#) == "Safari" && ego.violation(in: "ego-browser nodejs -e x") == nil, "named browser handling")
  let rpc = ComputerUseRPC()
  var events = 0
  rpc.event = { message in if message["method"] as? String == "test/event" { events += 1 } }
  try rpc.start(binary: CommandLine.arguments[1], environment: ProcessInfo.processInfo.environment)
  let response = try await rpc.call("split", [:])
  precondition(response["ok"] as? Bool == true && events == 1)
  do { _ = try await rpc.call("error", [:]); fatalError("RPC error ignored") } catch {}
  let waiting = Task { @MainActor in try await rpc.call("wait", [:]) }
  try await Task.sleep(nanoseconds: 20_000_000)
  rpc.stop()
  do { _ = try await waiting.value; fatalError("Stopped request succeeded") } catch {}
  do { _ = try await rpc.call("afterStop", [:]); fatalError("Stopped transport accepted work") } catch {}
  let exiting = ComputerUseRPC()
  try exiting.start(binary: CommandLine.arguments[1], environment: ProcessInfo.processInfo.environment)
  do { _ = try await exiting.call("exit", [:]); fatalError("EOF succeeded") } catch {}
  var prompts = 0
  for _ in 0..<2 {
   let result = try await CodexComputerUse.shared.run(request: "Fixture task", context: "", image: nil, history: [], connection: .localCodex, model: "test-model", reasoning: nil, progress: { _ in }, presentApproval: {
    prompts += 1
    let request = CodexComputerUse.shared.approval!
    CodexComputerUse.shared.answerApproval(id: request.id, answer: "Allowed in isolated fixture")
   })
   precondition(result == "Verified fixture result")
  }
  precondition(prompts == 4, "Routine permissions repeated, sensitive permissions skipped, or approval leaked across tasks")
  ToolPolicyStore.shared.computerUse = .allow
  let allowed = try await CodexComputerUse.shared.run(request: "Fixture task", context: "", image: nil, history: [], connection: .localCodex, model: "test-model", reasoning: nil, progress: { _ in }, presentApproval: {
   prompts += 1
   let request = CodexComputerUse.shared.approval!
   CodexComputerUse.shared.answerApproval(id: request.id, answer: "Allowed in isolated fixture")
  })
  precondition(allowed == "Verified fixture result" && prompts == 5, "Always allow must skip routine consent and still ask for sensitive actions")
  print("PASS: split JSONL, events, errors, cancellation, process exit, task consent reuse, sensitive consent, consent reset, always-allow policy, browser guard")
 }
}
'''
SERVER = '''#!/usr/bin/env python3
import sys,json,time
approvals=0
turn_started=False
def emit(value):print(json.dumps(value),flush=True)
def request(ident,risk):
 emit({'id':ident,'method':'mcpServer/elicitation/request','params':{'serverName':'cua_repl','mode':'form','message':'Fixture consent','requestedSchema':{'type':'object','properties':{}},'_meta':{'connector_id':'computer-use','riskLevel':risk}}})
for line in sys.stdin:
 r=json.loads(line); method=r.get('method'); ident=r.get('id')
 if method=='initialized':continue
 if method=='initialize':emit({'id':ident,'result':{}});continue
 if method=='mcpServerStatus/list':emit({'id':ident,'result':{'data':[{'name':'cua_repl','tools':{'js':{}}}]}});continue
 if method=='model/list':emit({'id':ident,'result':{'data':[{'id':'test-model'}]}});continue
 if method=='thread/start':emit({'id':ident,'result':{'thread':{'id':'fixture'}}});continue
 if method=='turn/start':
  emit({'id':ident,'result':{}});request(100,'low');continue
 if method is None and ident in [100,101,102]:
  assert r['result']['action']=='accept'
  if ident==100:request(101,'low')
  elif ident==101:request(102,'high')
  else:
   emit({'method':'item/completed','params':{'item':{'type':'agentMessage','text':'Verified fixture result','phase':'final_answer'}}})
   emit({'method':'turn/completed','params':{'turn':{'status':'completed'}}})
  continue
 if method=='wait':continue
 if method=='exit':sys.exit(0)
 if method=='error':print(json.dumps({'id':ident,'error':{'message':'expected failure'}}),flush=True);continue
 print(json.dumps({'method':'test/event','params':{}}),flush=True)
 data=json.dumps({'id':ident,'result':{'ok':True}})+'\\n'
 sys.stdout.write(data[:9]);sys.stdout.flush();time.sleep(.01)
 sys.stdout.write(data[9:]);sys.stdout.flush()
'''
with tempfile.TemporaryDirectory(prefix='speek-computer-check-') as folder:
 folder=pathlib.Path(folder)
 source=(ROOT/'Speek/Actions/CodexComputerUse.swift').read_text()
 transport=source
 (folder/'Transport.swift').write_text(STUB+transport)
 (folder/'Main.swift').write_text(MAIN)
 server=folder/'fake-codex';server.write_text(SERVER);server.chmod(0o700)
 subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(folder/'Transport.swift'),str(folder/'Main.swift'),'-o',str(folder/'check')],check=True)
 subprocess.run([str(folder/'check'),str(server)],check=True,timeout=15)
