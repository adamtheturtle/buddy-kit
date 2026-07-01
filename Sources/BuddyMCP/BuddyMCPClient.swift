//
//  BuddyMCPClient.swift
//  BuddyMCP
//
//  The MCP-client catalogue both host apps duplicated for their "how to add this server"
//  settings pane (#647, PadBuddy #501 / RankBuddy #74). Both defined the same four
//  clients - Claude Desktop, Claude Code, Codex, Cursor - with identical display names,
//  config-file paths, and, most importantly, identical snippet builders: the `mcpServers`
//  JSON block, the `claude mcp add …` CLI command, and the `[mcp_servers.X]` TOML table.
//  Those differed only in the server-name literal (`padbuddy` vs `rankbuddy`), so they're
//  lifted here parameterised on the server name.
//
//  What deliberately stays app-side: the sandboxed write-to-disk / JSON-merge / TOML-append
//  install machinery (PadBuddy's `MCPClientInstall`), each app's settings UI, and each app's
//  own troubleshooting / verify / restart copy, which diverges in wording. This module owns
//  only the data model and the ready-to-paste snippet, which are byte-identical across apps.
//

import Foundation

/// An MCP client a host app can give setup instructions (or install itself) for. The
/// service supplies its own server name; everything else - the display name, config path,
/// snippet format, and the snippet text - is shared.
public enum BuddyMCPClient: String, CaseIterable, Identifiable, Sendable {
    case claudeDesktop
    case claudeCode
    case codex
    case cursor

    public var id: String {
        rawValue
    }

    /// The client's human-facing name, shown as the settings tab title.
    public var displayName: String {
        switch self {
        case .claudeDesktop: "Claude Desktop"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    /// How this client is configured, which decides the snippet shape: a JSON `mcpServers`
    /// block, a shell command, or a TOML table.
    public enum Format: Sendable {
        case json
        case command
        case toml
    }

    /// The snippet format this client expects.
    public var format: Format {
        switch self {
        case .claudeDesktop, .cursor: .json
        case .claudeCode: .command
        case .codex: .toml
        }
    }

    /// Whether the snippet is a shell command to run (vs a config block to paste) - lets a
    /// settings UI relabel its copy button accordingly.
    public var isCommand: Bool {
        format == .command
    }

    /// The default config-file location for this client, e.g. for a "paste into …" hint.
    /// The path may not exist yet.
    public var configPath: String {
        switch self {
        case .claudeDesktop: "~/Library/Application Support/Claude/claude_desktop_config.json"
        case .claudeCode: "~/.claude.json"
        case .codex: "~/.codex/config.toml"
        case .cursor: "~/.cursor/mcp.json"
        }
    }

    /// The ready-to-use configuration (or command) that points this client at a host binary
    /// launched with `--mcp`.
    ///
    /// - Parameters:
    ///   - command: The launch command - the host app's own executable path.
    ///   - serverName: The MCP server name key, e.g. `"padbuddy"` or `"rankbuddy"`.
    public func configSnippet(command: String, serverName: String) -> String {
        switch format {
        case .json:
            // The `mcpServers` shape used by Claude Desktop and Cursor, pretty-printed with
            // sorted keys so it round-trips stably.
            let config: [String: Any] = [
                "mcpServers": [
                    serverName: ["command": command, "args": ["--mcp"]]
                ]
            ]
            let data = (try? JSONSerialization.data(
                withJSONObject: config, options: [.prettyPrinted, .sortedKeys]
            )) ?? Data("{}".utf8)
            return String(data: data, encoding: .utf8) ?? "{}"

        case .command:
            // Claude Code registers an MCP server from the CLI; `--` separates the host app's
            // own args from claude's so `--mcp` reaches the host binary.
            return "claude mcp add \(serverName) -- \"\(command)\" --mcp"

        case .toml:
            return """
            [mcp_servers.\(serverName)]
            command = "\(command)"
            args = ["--mcp"]
            """
        }
    }
}
