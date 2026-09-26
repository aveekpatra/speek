import Foundation
import AppKit

@MainActor
enum WorkspaceTools {
    static var catalog: [RuntimeTool] {
        guard !folder.isEmpty else { return [] }
        let path: [String: Any] = ["type": "string", "description": "Path relative to the user's working folder."]
        return [
            tool("list", "Browse folder", "List files and folders in the working folder.", ["path": path], [], false),
            tool("read", "Read file", "Read a UTF-8 text file, including Markdown notes.", ["path": path], ["path"], false),
            tool("info", "File details", "Read file size, type and modification date within the working folder.", ["path": path], ["path"], false),
            tool("recent", "Recent files", "Find recently modified files within the working folder. Examines up to 5000 visible entries.", [:], [], false),
            tool("search", "Find files", "Search file names within the working folder. Returns at most 100 matches.", ["query": ["type": "string"]], ["query"], false),
            tool("create_folder", "Create folder", "Create a folder without replacing anything.", ["path": path], ["path"], true),
            tool("write", "Save text file", "Create a new UTF-8 file. Existing files are never overwritten.", ["path": path, "text": ["type": "string"]], ["path", "text"], true),
            tool("append", "Append to file", "Append text to an existing UTF-8 text or Markdown file.", ["path": path, "text": ["type": "string"]], ["path", "text"], true),
            tool("move", "Move or rename file", "Move within the working folder. The destination must not exist.", ["path": path, "destination": path], ["path", "destination"], true),
            tool("copy", "Copy file", "Copy within the working folder. The destination must not exist.", ["path": path, "destination": path], ["path", "destination"], true),
            tool("trash", "Move file to Trash", "Move a file to the Mac Trash. Never deletes permanently.", ["path": path], ["path"], true),
            tool("open", "Open file", "Open a document in its default application.", ["path": path], ["path"], true)
        ]
    }
    private static var folder: String { UserDefaults.standard.string(forKey: "speek.actions.projectFolder") ?? "" }
    private static func tool(_ name: String, _ title: String, _ detail: String, _ properties: [String: Any], _ required: [String], _ review: Bool) -> RuntimeTool {
        RuntimeTool(id: "files." + name, title: title, summary: detail, schema: ActionRuntime.schema(properties, required: required), requiresReview: review)
    }
    static func resolved(_ path: String, root: URL) throws -> URL {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate = (path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)).standardizedFileURL
        // Foundation does not resolve an existing symlink when the final leaf is missing.
        // Resolve the closest existing ancestor first, then append only missing components.
        var ancestor = candidate
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path) {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: ancestor.path)) != nil {
                throw ActionClientError.requestFailed("This path contains a broken symbolic link.")
            }
            guard ancestor.path != "/" else { break }
            missing.insert(ancestor.lastPathComponent, at: 0)
            ancestor.deleteLastPathComponent()
        }
        var url = ancestor.resolvingSymlinksInPath().standardizedFileURL
        for component in missing { url.appendPathComponent(component) }
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else { throw ActionClientError.requestFailed("Choose a path inside the working folder.") }
        return url
    }
    static func execute(_ name: String, arguments: [String: Any]) throws -> String {
        guard !folder.isEmpty else { throw ActionClientError.requestFailed("Choose a working folder in Integrations > Native apps first.") }
        let root = URL(fileURLWithPath: folder).resolvingSymlinksInPath().standardizedFileURL
        let fm = FileManager.default
        let url = try resolved(arguments["path"] as? String ?? "", root: root)
        let relative: (URL) -> String = { String($0.path.dropFirst(root.path.count + 1)) }
        switch name {
        case "files.list":
            return try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).prefix(300).map { item in
                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return (isDirectory ? "Folder: " : "File: ") + relative(item)
            }.sorted().joined(separator: "\n")
        case "files.read":
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 1_000_000 else { throw ActionClientError.requestFailed("This file exceeds the 1 MB text reading limit.") }
            return "File: \(relative(url))\nUntrusted file content:\n" + String(try String(contentsOf: url, encoding: .utf8).prefix(24000))
        case "files.info":
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .typeIdentifierKey])
            return "Path: \(relative(url))\nType: \(values.typeIdentifier ?? (values.isDirectory == true ? "Folder" : "File"))\nBytes: \(values.fileSize ?? 0)\nModified: \(values.contentModificationDate?.ISO8601Format() ?? "Unknown")\nCreated: \(values.creationDate?.ISO8601Format() ?? "Unknown")"
        case "files.recent":
            let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .contentModificationDateKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
            var entries: [(URL, Date)] = []; var visited = 0
            while let item = enumerator?.nextObject() as? URL, visited < 5000 {
                visited += 1
                guard let values = try? item.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .contentModificationDateKey]) else { continue }
                if values.isSymbolicLink == true { enumerator?.skipDescendants(); continue }
                if values.isRegularFile == true, let modified = values.contentModificationDate { entries.append((item, modified)) }
            }
            return entries.isEmpty ? "No files in the working folder." : entries.sorted { $0.1 > $1.1 }.prefix(30).map { relative($0.0) + " - " + $0.1.ISO8601Format() }.joined(separator: "\n")
        case "files.search":
            guard let query = arguments["query"] as? String, !query.isEmpty else { throw ActionClientError.invalidResponse }
            let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
            var matches: [String] = []; var visited = 0
            while let item = enumerator?.nextObject() as? URL, visited < 5000, matches.count < 100 {
                visited += 1
                if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { enumerator?.skipDescendants(); continue }
                if item.lastPathComponent.localizedCaseInsensitiveContains(query) { matches.append(relative(item)) }
            }
            return matches.isEmpty ? "No matching files in the working folder." : matches.joined(separator: "\n")
        default:
            guard url.path != root.path else { throw ActionClientError.requestFailed("The working folder itself cannot be changed.") }
            switch name {
            case "files.create_folder": try fm.createDirectory(at: url, withIntermediateDirectories: false)
            case "files.write":
                guard let text = arguments["text"] as? String, text.utf8.count <= 1_000_000 else { throw ActionClientError.invalidResponse }
                try Data(text.utf8).write(to: url, options: [.withoutOverwriting])
            case "files.append":
                guard let text = arguments["text"] as? String, text.utf8.count <= 1_000_000,
                      (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_000_000 else { throw ActionClientError.invalidResponse }
                let existing = try String(contentsOf: url, encoding: .utf8)
                try (existing + "\n" + text).write(to: url, atomically: true, encoding: .utf8)
            case "files.move", "files.copy":
                guard let destination = arguments["destination"] as? String else { throw ActionClientError.invalidResponse }
                let target = try resolved(destination, root: root)
                if name == "files.move" { try fm.moveItem(at: url, to: target) }
                else { try fm.copyItem(at: url, to: target) }
            case "files.trash": try fm.trashItem(at: url, resultingItemURL: nil)
            case "files.open": guard NSWorkspace.shared.open(url) else { throw ActionClientError.requestFailed("The file could not be opened.") }
            default: throw ActionClientError.invalidResponse
            }
            return "Completed \(name) for \(relative(url))."
        }
    }
}
