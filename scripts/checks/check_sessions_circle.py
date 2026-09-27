"""Session boundaries and circle-gesture loop detection."""
import pathlib, subprocess, tempfile

root = pathlib.Path(__file__).resolve().parents[2]
stub = """
import AppKit
struct AssistantScreenContext { var label: String; var text: String; var image: Data?; var isRegion = false }
@MainActor final class ScreenContext { static let shared = ScreenContext()
  func captureCircled(_ loop: [NSPoint], on screen: NSScreen) async throws -> AssistantScreenContext { .init(label: "", text: "") } }
"""
check = """
import AppKit
@main struct Check { static func main() {
  func expect(_ ok: Bool, _ what: String) { if !ok { print("FAIL: " + what); exit(1) } }
  expect(SessionRouting.continues(idle: 120, refersBack: false), "recent turn continues")
  expect(!SessionRouting.continues(idle: 900, refersBack: false), "15 minutes idle starts fresh")
  expect(SessionRouting.continues(idle: 1800, refersBack: true), "referring back within an hour continues")
  expect(!SessionRouting.continues(idle: 5000, refersBack: true), "over an hour starts fresh")
  expect(SessionRouting.refersBack("send it to him"), "pronouns refer back")
  expect(!SessionRouting.refersBack("what's the weather in Prague"), "new topic does not")
  // A circle of radius 60 drawn over one second.
  var path: [NSPoint] = [], times: [TimeInterval] = []
  for i in 0...40 { let a = Double(i) / 40 * 2 * .pi; path.append(NSPoint(x: 300 + 60 * cos(a), y: 300 + 60 * sin(a))); times.append(Double(i) / 40) }
  expect(CircleGesture.loop(in: path, times: times) != nil, "circle detected")
  // Back and forth along a line is not a circle.
  var line: [NSPoint] = [], lineTimes: [TimeInterval] = []
  for i in 0...40 { let x = i <= 20 ? Double(i) * 10 : Double(40 - i) * 10; line.append(NSPoint(x: 100 + x, y: 100)); lineTimes.append(Double(i) / 40) }
  expect(CircleGesture.loop(in: line, times: lineTimes) == nil, "line rejected")
  // A tiny wiggle is not a circle.
  var small: [NSPoint] = [], smallTimes: [TimeInterval] = []
  for i in 0...40 { let a = Double(i) / 40 * 2 * .pi; small.append(NSPoint(x: 50 + 8 * cos(a), y: 50 + 8 * sin(a))); smallTimes.append(Double(i) / 40) }
  expect(CircleGesture.loop(in: small, times: smallTimes) == nil, "small wiggle rejected")
  print("PASS: session window, referring back, circle detection, lines and wiggles rejected")
} }
"""
with tempfile.TemporaryDirectory() as tmp:
    tmp = pathlib.Path(tmp)
    (tmp / "Stub.swift").write_text(stub); (tmp / "main.swift").write_text(check)
    binary = tmp / "check"
    subprocess.run(["swiftc", "-parse-as-library", "-o", str(binary), str(tmp / "Stub.swift"), str(tmp / "main.swift"),
                    str(root / "Speek/Assistant/CircleGesture.swift"), str(root / "Speek/Assistant/SessionRouting.swift")], check=True)
    subprocess.run([str(binary)], check=True)
