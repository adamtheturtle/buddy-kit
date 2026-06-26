//
//  ToolSchema.swift
//  BuddyMCP
//
//  Converts a host app's plumbing-neutral tool catalog - plain JSON descriptors
//  (`[String: Any]`) - into the swift-sdk's `Tool`/`Value` types. Keeping the catalog
//  as JSON lets an app define its tools once (names, descriptions, input schemas,
//  annotations) in a Foundation-only core and advertise the exact same list from both
//  an in-app server and a standalone CLI. This file is the generic descriptor->`Tool`
//  bridge; the catalog content itself stays app-side.
//

import Foundation
import MCP

/// Converts a JSON value from a catalog into an MCP `Value`. Order matters: `Bool` is
/// checked before the numeric types so a flag isn't read as an int. An already-built
/// `Value` passes through unchanged.
public func mcpValue(_ any: Any) -> Value {
    switch any {
    case let value as Value: value
    case let bool as Bool: .bool(bool)
    case let int as Int: .int(int)
    case let double as Double: .double(double)
    case let string as String: .string(string)
    case let array as [Any]: .array(array.map(mcpValue))
    case let object as [String: Any]: .object(object.mapValues(mcpValue))
    default: .null
    }
}

/// Turns one descriptor (`{ name, description, inputSchema, annotations? }`) into an
/// `MCP.Tool`. Missing `name`/`description` default to empty and a missing
/// `inputSchema` to an empty object, so a partial descriptor still yields a valid tool.
public func mcpTool(from descriptor: [String: Any]) -> Tool {
    let name = descriptor["name"] as? String ?? ""
    let description = descriptor["description"] as? String ?? ""
    let inputSchema = mcpValue(descriptor["inputSchema"] ?? [String: Any]())
    let annotations = (descriptor["annotations"] as? [String: Any]).map(mcpAnnotations)
        ?? Tool.Annotations()
    return Tool(name: name, description: description, inputSchema: inputSchema, annotations: annotations)
}

/// Builds `Tool.Annotations` from a descriptor's `annotations` sub-object.
public func mcpAnnotations(_ dict: [String: Any]) -> Tool.Annotations {
    Tool.Annotations(
        title: dict["title"] as? String,
        readOnlyHint: dict["readOnlyHint"] as? Bool,
        destructiveHint: dict["destructiveHint"] as? Bool,
        openWorldHint: dict["openWorldHint"] as? Bool
    )
}

/// Converts a whole catalog of JSON descriptors into the `Tool` list to advertise from
/// `tools/list`.
public func mcpTools(from descriptors: [[String: Any]]) -> [Tool] {
    descriptors.map(mcpTool)
}
