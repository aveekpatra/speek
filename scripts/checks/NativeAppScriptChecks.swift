import Foundation
import AppKit
@main struct Checks {
 @MainActor static func main() throws {
   for tool in NativeAppTools.catalog {
     _ = try JSONSerialization.jsonObject(with: Data(tool.inputSchemaJSON.utf8))
     if NSWorkspace.shared.urlForApplication(withBundleIdentifier:tool.service.bundleID) == nil { print("SKIP unavailable: \(tool.name)"); continue }
     var error:NSDictionary?
     let script=NSAppleScript(source:NativeAppTools.script(for:tool.name))!
     guard script.compileAndReturnError(&error) else { print("FAIL \(tool.name): \(String(describing:error))"); exit(1) }
     print("Compiled \(tool.name)")
   }
 }
}
