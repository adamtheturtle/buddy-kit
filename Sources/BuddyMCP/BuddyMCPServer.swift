//
//  BuddyMCPServer.swift
//  BuddyMCP
//
//  The service-agnostic server bootstrap. It wires an `MCPToolProvider` to the official
//  MCP Swift SDK: it creates the `Server`, registers the `tools`/`prompts`/`resources`
//  method handlers that forward to the provider, and runs it over a transport. This is
//  the piece every host app shared but each had hand-rolled; the provider is the only
//  app-specific input.
//

import Foundation
import MCP

/// Serves an `MCPToolProvider` over the official MCP Swift SDK.
///
/// Typical CLI use is one call:
/// ```swift
/// let server = BuddyMCPServer(name: "PadBuddy", version: "1.0", provider: myProvider)
/// try await server.run(transport: StdioTransport())
/// ```
/// An in-app server that manages its own lifetime can use `start(transport:)` instead of
/// `run`, keeping the returned-from handle alive without blocking on disconnect.
public struct BuddyMCPServer {
    private let server: Server
    private let provider: any MCPToolProvider

    /// Creates a server fronting `provider`. `capabilities` defaults to advertising
    /// tools, prompts and resources (none with change notifications); pass a narrower
    /// set for a tools-only server.
    public init(
        name: String,
        version: String,
        capabilities: Server.Capabilities = .init(
            prompts: .init(listChanged: false),
            resources: .init(subscribe: false, listChanged: false),
            tools: .init(listChanged: false)
        ),
        provider: any MCPToolProvider
    ) {
        server = Server(name: name, version: version, capabilities: capabilities)
        self.provider = provider
    }

    /// Registers the provider-backed handlers and starts the server over `transport`,
    /// returning once it is running. The caller keeps the server alive.
    public func start(transport: some Transport) async throws {
        await registerHandlers()
        try await server.start(transport: transport)
    }

    /// Registers handlers, starts the server, and waits until the client disconnects -
    /// the all-in-one entry point a host's `main` calls.
    public func run(transport: some Transport) async throws {
        try await start(transport: transport)
        await server.waitUntilCompleted()
    }

    /// Forwards each MCP method to the provider. Required methods (`tools/*`) always
    /// resolve; optional ones use the provider's defaults (empty lists, "unknown"
    /// errors) unless it overrides them. `PromptError` is mapped to a JSON-RPC error.
    private func registerHandlers() async {
        let provider = provider

        await server.withMethodHandler(ListTools.self) { _ in
            await ListTools.Result(tools: provider.tools())
        }

        await server.withMethodHandler(CallTool.self) { params in
            await provider.callTool(params.name, arguments: params.arguments)
        }

        await server.withMethodHandler(ListPrompts.self) { _ in
            await ListPrompts.Result(prompts: provider.prompts())
        }

        await server.withMethodHandler(GetPrompt.self) { params in
            do {
                return try await provider.getPrompt(params.name, arguments: params.arguments)
            } catch let PromptError.unknownPrompt(name) {
                throw MCPError.invalidParams("Unknown prompt: \(name)")
            } catch let PromptError.missingArgument(name) {
                throw MCPError.invalidParams("Missing required argument: \(name)")
            }
        }

        await server.withMethodHandler(ListResources.self) { _ in
            await ListResources.Result(resources: provider.resources())
        }

        await server.withMethodHandler(ListResourceTemplates.self) { _ in
            await ListResourceTemplates.Result(templates: provider.resourceTemplates())
        }

        await server.withMethodHandler(ReadResource.self) { params in
            try await provider.readResource(params.uri)
        }
    }
}
