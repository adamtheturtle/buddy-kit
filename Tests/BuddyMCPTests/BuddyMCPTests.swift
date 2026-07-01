//
//  BuddyMCPTests.swift
//  BuddyMCPTests
//
//  Exercises the service-agnostic MCP scaffolding: argument coercion, the JSON
//  descriptor -> Tool bridge, the result builders, the prompt helpers, and the
//  MCPToolProvider default implementations. The server bootstrap is thin glue over the
//  SDK; these prove the reusable logic a host app builds on.
//

import Foundation
import MCP
import Testing

@testable import BuddyMCP

@Suite("Argument coercion")
struct ArgumentTests {
    @Test
    func `stringArgument coerces ints and doubles and rejects non-scalars`() {
        let args: [String: Value] = ["s": .string("hi"), "i": .int(5), "d": .double(2.5), "a": .array([])]
        #expect(stringArgument(args, "s") == "hi")
        #expect(stringArgument(args, "i") == "5")
        #expect(stringArgument(args, "d") == "2.5")
        #expect(stringArgument(args, "a") == nil)
        #expect(stringArgument(args, "missing") == nil)
        #expect(stringArgument(nil, "s") == nil)
    }

    @Test
    func `intArgument truncates doubles and parses numeric strings`() {
        let args: [String: Value] = ["i": .int(7), "d": .double(3.9), "s": .string("42"), "bad": .string("nope")]
        #expect(intArgument(args, "i") == 7)
        #expect(intArgument(args, "d") == 3)
        #expect(intArgument(args, "s") == 42)
        #expect(intArgument(args, "bad") == nil)
        #expect(intArgument(args, "missing") == nil)
    }

    @Test
    func `optionalString trims and nils empties`() {
        let args: [String: Value] = ["x": .string("  hello  "), "blank": .string("   ")]
        #expect(optionalString(args, "x") == "hello")
        #expect(optionalString(args, "blank") == nil)
        #expect(optionalString(args, "missing") == nil)
    }
}

@Suite("Tool schema bridge")
struct ToolSchemaTests {
    @Test
    func `mcpValue maps each JSON type, checking Bool before Int`() {
        #expect(mcpValue(true) == .bool(true))
        #expect(mcpValue(5) == .int(5))
        #expect(mcpValue(2.5) == .double(2.5))
        #expect(mcpValue("x") == .string("x"))
        #expect(mcpValue([1, "a"]) == .array([.int(1), .string("a")]))
        #expect(mcpValue(["k": 1]) == .object(["k": .int(1)]))
        // An already-built Value passes through unchanged.
        #expect(mcpValue(Value.string("y")) == .string("y"))
    }

    @Test
    func `mcpTool reads name, description, schema and annotations`() {
        let descriptor: [String: Any] = [
            "name": "list_things",
            "description": "Lists things.",
            "inputSchema": ["type": "object", "properties": ["page": ["type": "integer"]]],
            "annotations": ["title": "List things", "readOnlyHint": true, "destructiveHint": false]
        ]
        let tool = mcpTool(from: descriptor)
        #expect(tool.name == "list_things")
        #expect(tool.description == "Lists things.")
        #expect(tool.annotations.title == "List things")
        #expect(tool.annotations.readOnlyHint == true)
        #expect(tool.annotations.destructiveHint == false)
        #expect(tool.inputSchema == .object([
            "type": .string("object"),
            "properties": .object(["page": .object(["type": .string("integer")])])
        ]))
    }

    @Test
    func `mcpTool tolerates a partial descriptor`() {
        let tool = mcpTool(from: ["name": "bare"])
        #expect(tool.name == "bare")
        #expect(tool.description == "")
        #expect(tool.inputSchema == .object([:]))
    }

    @Test
    func `mcpTools converts a whole catalog`() {
        let tools = mcpTools(from: [["name": "a"], ["name": "b"]])
        #expect(tools.map(\.name) == ["a", "b"])
    }
}

@Suite("Result builders")
struct ResultTests {
    private func text(of result: CallTool.Result) -> String? {
        guard case let .text(text, _, _) = result.content.first else { return nil }

        return text
    }

    @Test
    func `textResult carries the text and optional error flag`() {
        #expect(text(of: textResult("ok")) == "ok")
        #expect(textResult("ok").isError == nil)
        #expect(errorResult("bad").isError == true)
        #expect(text(of: errorResult("bad")) == "bad")
    }

    @Test
    func `missingArgument names the argument and is an error`() {
        let result = missingArgument("pad")
        #expect(text(of: result)?.contains("pad") == true)
        #expect(result.isError == true)
    }

    @Test
    func `jsonResult encodes sorted, decodable JSON`() throws {
        let result = jsonResult(["b": 2, "a": 1])
        let json = try #require(text(of: result))
        // Keys are sorted, so "a" precedes "b" in the serialized form.
        #expect(json.range(of: "\"a\"")!.lowerBound < json.range(of: "\"b\"")!.lowerBound)
        let decoded = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Int]
        #expect(decoded == ["a": 1, "b": 2])
    }
}

@Suite("Prompt helpers")
struct PromptHelperTests {
    @Test
    func `promptArgument trims and nils empties`() {
        #expect(promptArgument(["t": "  hi  "], "t") == "hi")
        #expect(promptArgument(["t": "   "], "t") == nil)
        #expect(promptArgument(nil, "t") == nil)
    }

    @Test
    func `requiredPromptArgument throws for an absent argument`() throws {
        #expect(try requiredPromptArgument(["t": "x"], "t") == "x")
        #expect(throws: PromptError.missingArgument("t")) {
            try requiredPromptArgument([:], "t")
        }
    }
}

@Suite("Stdio bootstrap")
struct StdioBootstrapTests {
    @Test
    func `wantsStdioMCP detects the flag past the executable path`() {
        #expect(BuddyMCPServer.wantsStdioMCP(["/path/to/app", "--mcp"]))
        #expect(BuddyMCPServer.wantsStdioMCP(["/path/to/app", "--other", "--mcp"]))
        #expect(!BuddyMCPServer.wantsStdioMCP(["/path/to/app"]))
        #expect(!BuddyMCPServer.wantsStdioMCP(["/path/to/app", "--other"]))
        // The flag in argv[0] (the executable path itself) doesn't count.
        #expect(!BuddyMCPServer.wantsStdioMCP(["--mcp"]))
    }

    @Test
    func `stdioModeFlag is the conventional --mcp`() {
        #expect(BuddyMCPServer.stdioModeFlag == "--mcp")
    }
}

/// A small `Codable & Sendable` entry for exercising `JSONLLog` round-trips.
private struct LogRow: Codable, Sendable, Equatable {
    let n: Int
    let text: String
}

@Suite("JSONL log")
struct JSONLLogTests {
    /// A log in a fresh temp directory, plus that directory (so a test can inspect/tear it
    /// down). Each call gets a unique directory so tests don't collide.
    private func makeLog(maxEntries: Int) -> (log: JSONLLog<LogRow>, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "JSONLLogTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let log = JSONLLog<LogRow>(directory: directory, fileName: "log.jsonl", maxEntries: maxEntries)
        return (log, directory)
    }

    @Test
    func `append then load round-trips entries oldest first`() {
        let (log, directory) = makeLog(maxEntries: 30)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rows = [LogRow(n: 1, text: "a"), LogRow(n: 2, text: "b"), LogRow(n: 3, text: "c")]
        for row in rows { log.append(row) }

        #expect(log.load() == rows)
    }

    @Test
    func `load skips a malformed line`() throws {
        let (log, directory) = makeLog(maxEntries: 30)
        defer { try? FileManager.default.removeItem(at: directory) }

        log.append(LogRow(n: 1, text: "a"))
        // Inject a torn/garbage line between two valid ones, as a concurrent append might.
        let url = directory.appending(path: "log.jsonl")
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{not json}\n".utf8))
        try handle.close()
        log.append(LogRow(n: 2, text: "b"))

        #expect(log.load() == [LogRow(n: 1, text: "a"), LogRow(n: 2, text: "b")])
    }

    @Test
    func `load caps at maxEntries keeping the newest`() {
        let (log, directory) = makeLog(maxEntries: 3)
        defer { try? FileManager.default.removeItem(at: directory) }

        for n in 1 ... 10 { log.append(LogRow(n: n, text: "\(n)")) }

        // The last three appended survive the read cap, oldest of those first.
        #expect(log.load().map(\.n) == [8, 9, 10])
    }

    @Test
    func `trim rewrites the file down to the cap`() throws {
        let (log, directory) = makeLog(maxEntries: 3)
        defer { try? FileManager.default.removeItem(at: directory) }

        for n in 1 ... 10 { log.append(LogRow(n: n, text: "\(n)")) }
        log.trim()

        // After trimming, the on-disk file itself holds only the last three lines.
        let url = directory.appending(path: "log.jsonl")
        let text = try String(contentsOf: url, encoding: .utf8)
        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: true).count
        #expect(lineCount == 3)
        #expect(log.load().map(\.n) == [8, 9, 10])
    }

    @Test
    func `clear removes the file so load returns empty`() {
        let (log, directory) = makeLog(maxEntries: 30)
        defer { try? FileManager.default.removeItem(at: directory) }

        log.append(LogRow(n: 1, text: "a"))
        #expect(!log.load().isEmpty)
        log.clear()
        #expect(log.load().isEmpty)
    }
}

@Suite("MCP client catalogue")
struct BuddyMCPClientTests {
    @Test
    func `every client snippet carries the server name and command`() {
        // A slash-free command so the assertion isn't tripped by JSON's forward-slash
        // escaping (the JSON builder emits "\/", matching both apps' real output).
        let command = "PadBuddyExecutable"
        for client in BuddyMCPClient.allCases {
            let snippet = client.configSnippet(command: command, serverName: "padbuddy")
            #expect(snippet.contains("padbuddy"), "\(client) snippet missing server name")
            #expect(snippet.contains(command), "\(client) snippet missing command")
        }
    }

    @Test
    func `snippet format matches the client`() {
        #expect(BuddyMCPClient.claudeDesktop.configSnippet(command: "cmd", serverName: "rankbuddy")
            .contains("\"mcpServers\""))
        #expect(BuddyMCPClient.cursor.configSnippet(command: "cmd", serverName: "rankbuddy")
            .contains("\"mcpServers\""))
        #expect(BuddyMCPClient.claudeCode.configSnippet(command: "cmd", serverName: "rankbuddy")
            .hasPrefix("claude mcp add rankbuddy"))
        #expect(BuddyMCPClient.codex.configSnippet(command: "cmd", serverName: "rankbuddy")
            .contains("[mcp_servers.rankbuddy]"))
    }

    @Test
    func `display names and command flag are stable`() {
        #expect(BuddyMCPClient.allCases.map(\.displayName)
            == ["Claude Desktop", "Claude Code", "Codex", "Cursor"])
        #expect(BuddyMCPClient.claudeCode.isCommand)
        #expect(!BuddyMCPClient.codex.isCommand)
    }
}

/// A minimal provider that only implements the two required methods, so the optional
/// prompt/resource defaults are exercised.
private struct ToolsOnlyProvider: MCPToolProvider {
    func tools() async -> [Tool] {
        [Tool(name: "ping", description: "Ping.", inputSchema: .object([:]))]
    }

    func callTool(_ name: String, arguments: [String: Value]?) async -> CallTool.Result {
        name == "ping" ? textResult("pong") : errorResult("Unknown tool: \(name)")
    }
}

@Suite("MCPToolProvider defaults")
struct ProviderDefaultTests {
    private let provider = ToolsOnlyProvider()

    @Test
    func `tools and callTool work as implemented`() async {
        #expect(await provider.tools().map(\.name) == ["ping"])
        let pong = await provider.callTool("ping", arguments: nil)
        guard case let .text(text, _, _) = pong.content.first else { Issue.record("no text"); return }

        #expect(text == "pong")
    }

    @Test
    func `prompts and resources default to empty`() async {
        #expect(await provider.prompts().isEmpty)
        #expect(await provider.resources().isEmpty)
        #expect(await provider.resourceTemplates().isEmpty)
    }

    @Test
    func `getPrompt defaults to throwing unknownPrompt`() async {
        await #expect(throws: PromptError.unknownPrompt("x")) {
            try await provider.getPrompt("x", arguments: nil)
        }
    }

    @Test
    func `readResource defaults to throwing`() async {
        await #expect(throws: (any Error).self) {
            try await provider.readResource("buddy://nope")
        }
    }
}
