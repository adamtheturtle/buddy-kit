//
//  MCPToolProvider.swift
//  BuddyMCP
//
//  The host-app seam. A service (PadBuddy for CoderPad, RankBuddy for HackerRank)
//  implements this protocol with its own concrete tool catalog, dispatch, prompts,
//  resources and account model; `BuddyMCPServer` wires whatever it returns to the
//  official MCP Swift SDK. Everything here is service-agnostic - the protocol mentions
//  no CoderPad/HackerRank type - so two apps share one server bootstrap and differ only
//  in their provider.
//

import Foundation
import MCP

/// What a host app supplies so `BuddyMCPServer` can serve it over MCP.
///
/// Only `tools()` and `callTool(_:arguments:)` are required; prompts and resources are
/// optional and default to empty, so a tools-only server needs nothing else. The
/// provider owns its own account resolution and write-gating inside `callTool` - those
/// are service-specific, and the generic argument-coercion / result-builder helpers in
/// this module make them easy to express.
public protocol MCPToolProvider: Sendable {
    /// The tools to advertise from `tools/list`. Async so a provider can gate the list
    /// on its configuration (which accounts exist, whether writes are opted in).
    func tools() async -> [Tool]

    /// Handle a `tools/call`. The provider resolves the target account, enforces any
    /// write opt-in, dispatches to its backend, and shapes the result.
    func callTool(_ name: String, arguments: [String: Value]?) async -> CallTool.Result

    /// The prompt templates to advertise from `prompts/list`. Defaults to none.
    func prompts() async -> [Prompt]

    /// Render a prompt for `prompts/get`. Throw `PromptError` (or any `Error`) to signal
    /// an unknown prompt or a missing argument. Defaults to "unknown prompt".
    func getPrompt(_ name: String, arguments: [String: String]?) async throws -> GetPrompt.Result

    /// The concrete resources to advertise from `resources/list`. Defaults to none.
    func resources() async -> [Resource]

    /// The URI templates to advertise from `resources/templates/list`. Defaults to none.
    func resourceTemplates() async -> [Resource.Template]

    /// Read the resource at `uri` for `resources/read`. Throw to signal an unknown URI
    /// or a fetch failure. Defaults to "unknown resource".
    func readResource(_ uri: String) async throws -> ReadResource.Result
}

public extension MCPToolProvider {
    func prompts() async -> [Prompt] { [] }

    func getPrompt(_ name: String, arguments: [String: String]?) async throws -> GetPrompt.Result {
        throw PromptError.unknownPrompt(name)
    }

    func resources() async -> [Resource] { [] }

    func resourceTemplates() async -> [Resource.Template] { [] }

    func readResource(_ uri: String) async throws -> ReadResource.Result {
        throw MCPError.invalidParams("Unknown resource URI: \(uri)")
    }
}
