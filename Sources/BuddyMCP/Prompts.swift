//
//  Prompts.swift
//  BuddyMCP
//
//  Generic scaffolding for MCP prompts, lifted from the coderpad MCP core. Prompts are
//  pre-written, argument-driven instruction templates a client can offer as
//  slash-commands. The catalog and the rendered text are app-specific (they name the
//  app's tools), but the error type and the argument-reading helpers are not, so they
//  live here for every host app's `getPrompt` to reuse.
//

import Foundation
import MCP

/// Raised when a prompt can't be rendered. A host's `MCPToolProvider.getPrompt` throws
/// these and `BuddyMCPServer` maps them to JSON-RPC `invalidParams` errors.
public enum PromptError: Swift.Error, Equatable {
    case unknownPrompt(String)
    case missingArgument(String)
}

/// A trimmed, non-empty value for `key` in a prompt's arguments, or nil.
public func promptArgument(_ arguments: [String: String]?, _ key: String) -> String? {
    guard let raw = arguments?[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
    else { return nil }

    return raw
}

/// A single required prompt argument, throwing `PromptError.missingArgument` when absent.
public func requiredPromptArgument(_ arguments: [String: String]?, _ key: String) throws -> String {
    guard let value = promptArgument(arguments, key) else { throw PromptError.missingArgument(key) }

    return value
}

/// A user-role text message, the common building block of a rendered prompt.
public func userPromptMessage(_ text: String) -> Prompt.Message {
    .user(.text(text: text))
}
