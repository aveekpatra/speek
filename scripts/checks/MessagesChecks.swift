import Foundation
import SQLite3
import AppKit
@main struct Checks {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("chat.db")
        var db: OpaquePointer?
        assert(sqlite3_open(url.path, &db) == SQLITE_OK)
        let schema = """
        CREATE TABLE message (text TEXT,date INTEGER,is_from_me INTEGER,is_read INTEGER,handle_id INTEGER,service TEXT);
        CREATE TABLE chat (guid TEXT,chat_identifier TEXT,display_name TEXT);
        CREATE TABLE chat_message_join (chat_id INTEGER,message_id INTEGER);
        CREATE TABLE handle (id TEXT);
        INSERT INTO handle VALUES ('+12025550123');
        INSERT INTO chat VALUES ('iMessage;-;+12025550123','+12025550123','Example');
        INSERT INTO message VALUES ('Hello world',800000000000000000,0,0,1,'iMessage');
        INSERT INTO message VALUES (NULL,800000010000000000,0,0,1,'iMessage');
        INSERT INTO message VALUES ('SMS only',800000020000000000,0,0,1,'SMS');
        INSERT INTO chat_message_join VALUES (1,1),(1,2),(1,3);
        CREATE TABLE attachment (filename TEXT,transfer_name TEXT);
        CREATE TABLE message_attachment_join (message_id INTEGER,attachment_id INTEGER);
        INSERT INTO attachment VALUES ('~/Library/Messages/Attachments/ab/photo.jpg','photo.jpg');
        INSERT INTO message_attachment_join VALUES (2,1);
        """
        assert(sqlite3_exec(db,schema,nil,nil,nil) == SQLITE_OK); sqlite3_close(db)
        let original = try Data(contentsOf:url)
        let store = MessagesDatabase(url:url)
        let recent = try store.read(operation:"messages.recent")
        assert(recent.items.count == 1); assert(recent.items[0]["unreadCount"] == "2")
        let conversation = try store.read(operation:"messages.conversation",conversationID:"iMessage;-;+12025550123")
        assert(conversation.items.count == 2); assert(conversation.items[0]["text"] == "Hello world")
        assert(conversation.items[1]["textAvailable"] == "false")
        assert(conversation.items[1]["attachments"] == "photo.jpg" && conversation.items[1]["text"] == "Attachment only: photo.jpg")
        assert(conversation.items[1]["attachmentPaths"] == NSHomeDirectory() + "/Library/Messages/Attachments/ab/photo.jpg")
        let search = try store.read(operation:"messages.search",query:"hello")
        assert(search.items.count == 1)
        let injected = try store.read(operation:"messages.search",query:"' OR 1=1 --")
        assert(injected.items.isEmpty)
        let unread = try store.read(operation:"messages.unread",limit:1)
        assert(unread.items.count == 1)
        let after = try Data(contentsOf:url); assert(after == original)
        let wrongURL=folder.appendingPathComponent("wrong.db")
        assert(sqlite3_open(wrongURL.path,&db) == SQLITE_OK)
        sqlite3_exec(db,"CREATE TABLE message (body TEXT)",nil,nil,nil);sqlite3_close(db)
        do { _=try MessagesDatabase(url:wrongURL).read(operation:"messages.recent"); assertionFailure() } catch { assert(error.localizedDescription.contains("not supported")) }
        assert(MessagesTools.isValidRecipient("+12025550123")); assert(MessagesTools.isValidRecipient("person@example.com"))
        assert(!MessagesTools.isValidRecipient("+12025550123\n")); assert(!MessagesTools.isValidRecipient("Mom"));assert(!MessagesTools.isValidRecipient("a@example.com;b@example.com"))
        do { _=try await MessagesTools.shared.execute(name:"messages.send",argumentsJSON:"{}");assertionFailure() } catch { assert(error.localizedDescription.contains("Review")) }
        var scriptError: NSDictionary?
        assert(NSAppleScript(source:MessagesTools.sendScript)!.compileAndReturnError(&scriptError),String(describing:scriptError))
        for tool in MessagesTools.catalog { _=try JSONSerialization.jsonObject(with:Data(tool.inputSchemaJSON.utf8)) }
        print("PASS: fake database recent/search/conversation/unread, null text, SMS exclusion, bound SQL injection, read-only bytes, schema failure, exact recipient validation, send approval gate, send script compile only")
    }
}
