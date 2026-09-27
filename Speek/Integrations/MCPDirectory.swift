import Foundation

/// Hosted MCP servers Speek can add in one step. Checked 2026-09-27 against each server's
/// published OAuth metadata: Notion, Linear, and Composio allow dynamic client registration;
/// GitHub accepts the GitHub CLI login as a bearer token; Gmail and Google Calendar need the
/// user's own Google Cloud OAuth client; Outlook and Slack connect through Composio.
struct MCPDirectoryEntry: Identifiable {
    enum Access: Equatable {
        case signIn
        case token(label: String, help: URL)
        /// The bearer token comes from a CLI the user is already signed in to.
        case command(String, tool: String)
        /// Sign-in with the user's own OAuth client (Google does not allow dynamic registration).
        case ownClient(scopes: String, help: URL)
        case viaComposio
    }

    let id: String
    let name: String
    let summary: String
    let endpoint: String
    let logo: String
    let access: Access

    var plugin: MCPPlugin {
        var plugin = MCPPlugin(name: name, transport: .http, endpoint: endpoint, directoryID: id)
        if case .command(let command, _) = access { plugin.tokenCommand = command }
        if case .ownClient(let scopes, _) = access { plugin.oauthScopes = scopes }
        return plugin
    }

    var accessLabel: String {
        switch access {
        case .signIn: return "Sign in with " + name
        case .token: return "Needs a personal access token"
        case .command(_, let tool): return "Uses your " + tool + " sign-in"
        case .ownClient: return "Sign in with Google"
        case .viaComposio: return "Connects through Composio"
        }
    }

    static let composio = MCPDirectoryEntry(
        id: "composio", name: "Composio", summary: "Outlook, Slack, and hundreds more apps through one connection.",
        endpoint: "https://connect.composio.dev/mcp", logo: "mcp-composio", access: .signIn)

    static let all: [MCPDirectoryEntry] = [
        MCPDirectoryEntry(id: "notion", name: "Notion", summary: "Search, read, create, and update pages and databases.",
                          endpoint: "https://mcp.notion.com/mcp", logo: "mcp-notion", access: .signIn),
        MCPDirectoryEntry(id: "linear", name: "Linear", summary: "Find, create, and update issues, projects, and comments.",
                          endpoint: "https://mcp.linear.app/mcp", logo: "mcp-linear", access: .signIn),
        MCPDirectoryEntry(id: "github", name: "GitHub", summary: "Repositories, issues, pull requests, and code search.",
                          endpoint: "https://api.githubcopilot.com/mcp/", logo: "mcp-github", access: .command("gh auth token", tool: "GitHub CLI")),
        composio,
        MCPDirectoryEntry(id: "gmail", name: "Gmail", summary: "Search and read email, and write drafts.",
                          endpoint: "https://gmailmcp.googleapis.com/mcp/v1", logo: "mcp-gmail",
                          access: .ownClient(scopes: "https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.compose https://www.googleapis.com/auth/gmail.modify",
                                             help: googleSetup)),
        MCPDirectoryEntry(id: "googlecalendar", name: "Google Calendar", summary: "See your schedule, find time, and manage events.",
                          endpoint: "https://calendarmcp.googleapis.com/mcp/v1", logo: "mcp-googlecalendar",
                          access: .ownClient(scopes: "https://www.googleapis.com/auth/calendar.calendarlist.readonly https://www.googleapis.com/auth/calendar.events",
                                             help: googleSetup)),
        MCPDirectoryEntry(id: "outlook", name: "Outlook", summary: "Mail and calendar for Microsoft 365 and Outlook.",
                          endpoint: composio.endpoint, logo: "mcp-outlook", access: .viaComposio),
        MCPDirectoryEntry(id: "slack", name: "Slack", summary: "Read and search conversations, and send messages.",
                          endpoint: composio.endpoint, logo: "mcp-slack", access: .viaComposio),
    ]

    static let googleSetup = URL(string: "https://developers.google.com/workspace/guides/configure-mcp-servers")!

    static func logo(for plugin: MCPPlugin) -> String? {
        plugin.directoryID.flatMap { id in all.first { $0.id == id }?.logo }
    }
}
