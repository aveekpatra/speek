#!/usr/bin/env python3
"""Compile real runtime helpers against small host stubs and check boundaries."""
import pathlib
import subprocess
import tempfile
ROOT = pathlib.Path(__file__).resolve().parents[2]
STUB = '''import Foundation
struct RuntimeTool { let id:String; let title:String; let summary:String; let schema:[String:Any]; let requiresReview:Bool }
enum ActionClientError: Error { case requestFailed(String), invalidResponse }
enum ActionRuntime { static func schema(_ properties:[String:Any], required:[String])->[String:Any] { ["type":"object","properties":properties,"required":required,"additionalProperties":false] } }
'''
TEST = r'''import Foundation
import AVFoundation
@main struct Checks {
 @MainActor static func main() throws {
  let spec:[String:Any] = ["type":"object","required":["count"],"properties":["count":["type":"integer","minimum":1,"maximum":5]],"additionalProperties":false]
  try ToolArguments.validate(["count":3],schema:spec)
  for bad:[String:Any] in [[:],["count":true],["count":0],["count":2.5],["count":3,"extra":1]] {
   do { try ToolArguments.validate(bad,schema:spec); fatalError("Invalid arguments accepted") } catch {}
  }
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:root) }
  assert(try WorkspaceTools.resolved("notes/a.md",root:root).path == root.appendingPathComponent("notes/a.md").path)
  do { _ = try WorkspaceTools.resolved("../escape",root:root); fatalError("Escaped folder") } catch {}
  try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("outside"),withDestinationURL:root.deletingLastPathComponent())
  do { _ = try WorkspaceTools.resolved("outside/escape",root:root); fatalError("Escaped symlink") } catch {}
  let source=root.appendingPathComponent("long.wav")
  let format=AVAudioFormat(standardFormatWithSampleRate:16000,channels:1)!
  let frames:AVAudioFrameCount=16000*330
  do {
   let file=try AVAudioFile(forWriting:source,settings:format.settings)
   let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:frames)!
   buffer.frameLength=frames
   memset(buffer.floatChannelData![0],0,Int(frames)*4)
   try file.write(from:buffer)
  }
  let chunks=try AudioChunks.splitIfNeeded(source)
  defer { for chunk in chunks where chunk != source { try? FileManager.default.removeItem(at:chunk) } }
  assert(chunks.count > 1)
  let total=try chunks.map { try AVAudioFile(forReading:$0).length }.reduce(0,+)
  assert(total == AVAudioFramePosition(frames))
  for chunk in chunks { assert((try chunk.resourceValues(forKeys:[.fileSizeKey]).fileSize!) < 20_000_000) }
  print("PASS: argument types, required/unknown fields, bounds, folder traversal, symlinks, lossless audio chunk frames and upload limits")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='speek-runtime-check-') as tmp:
    tmp = pathlib.Path(tmp)
    (tmp/'Stubs.swift').write_text(STUB)
    (tmp/'Main.swift').write_text(TEST.replace('assert(try WorkspaceTools.resolved("notes/a.md",root:root).path == root.appendingPathComponent("notes/a.md").path)', 'let resolved = try WorkspaceTools.resolved("notes/a.md",root:root); assert(resolved.path == root.appendingPathComponent("notes/a.md").path)').replace('assert((try chunk.resourceValues(forKeys:[.fileSizeKey]).fileSize!) < 20_000_000)', 'let size = try chunk.resourceValues(forKeys:[.fileSizeKey]).fileSize!; assert(size < 20_000_000)'))
    sources = ['Speek/Runtime/ToolArguments.swift','Speek/Runtime/WorkspaceTools.swift','Speek/Assistant/AudioChunks.swift']
    subprocess.run(['swiftc','-swift-version','6','-parse-as-library',str(tmp/'Stubs.swift'),*[str(ROOT/s) for s in sources],str(tmp/'Main.swift'),'-o',str(tmp/'checks')],check=True)
    subprocess.run([str(tmp/'checks')],check=True)
