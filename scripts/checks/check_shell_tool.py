#!/usr/bin/env python3
"""Run the production shell tool against real commands with minimal stubs."""
import pathlib, subprocess, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[2]
STUB = '''import Foundation
enum ActionClientError: Error { case requestFailed(String) }
struct RuntimeTool { let id: String; let title: String; let summary: String; let schema: [String: Any]; let requiresReview: Bool }
@MainActor enum ActionRuntime { static func schema(_ p: [String: Any], required: [String]) -> [String: Any] { ["properties": p, "required": required] } }
'''
MAIN = '''import Foundation
@main struct Checks {
 static func main() async throws {
  let folder = CommandLine.arguments[1]
  let echo = try await ShellTool.execute(arguments: ["command": "echo hello; pwd", "workingDirectory": folder])
  precondition(echo.contains("Exit code: 0") && echo.contains("hello") && echo.contains(folder), echo)
  let failing = try await ShellTool.execute(arguments: ["command": "echo oops >&2; exit 3"])
  precondition(failing.contains("Exit code: 3") && failing.contains("oops"), failing)
  let big = try await ShellTool.execute(arguments: ["command": "yes x | head -c 50000"])
  precondition(big.contains("[Output truncated]"), "Output was not capped")
  do { _ = try await ShellTool.execute(arguments: ["command": "  "]); fatalError("Empty command ran") } catch {}
  print("PASS: output and stderr, exit codes, working directory, output cap, empty command")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='speek-shell-check-') as tmp:
    folder = pathlib.Path(tmp).resolve()
    (folder/'Stub.swift').write_text(STUB)
    (folder/'Main.swift').write_text(MAIN)
    subprocess.run(['swiftc', '-parse-as-library', str(ROOT/'Speek/Runtime/ShellTool.swift'), str(folder/'Stub.swift'), str(folder/'Main.swift'), '-o', str(folder/'check')], check=True)
    subprocess.run([str(folder/'check'), str(folder)], check=True)
