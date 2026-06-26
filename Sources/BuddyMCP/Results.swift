//
//  Results.swift
//  BuddyMCP
//
//  Generic `CallTool.Result` builders shared by every host app's tool dispatch, lifted
//  from the coderpad MCP executable. They wrap the swift-sdk's verbose content-enum
//  initializers (`.text(text:annotations:_meta:)`) so dispatch code reads cleanly.
//

import Foundation
import MCP

/// A plain-text tool result. `isError` nil marks success; pass `true` to flag a
/// tool-level error the client should surface.
public func textResult(_ text: String, isError: Bool? = nil) -> CallTool.Result {
    CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: isError)
}

/// An error tool result carrying `message`.
public func errorResult(_ message: String) -> CallTool.Result {
    textResult(message, isError: true)
}

/// The standard "missing required argument" error result.
public func missingArgument(_ name: String) -> CallTool.Result {
    errorResult("Missing required argument: \(name)")
}

/// Encodes a result dictionary as pretty, key-sorted JSON text, or an error result when
/// it can't be serialized.
public func jsonResult(_ object: [String: Any]) -> CallTool.Result {
    guard let data = try? JSONSerialization.data(
        withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
    ) else {
        return errorResult("Could not encode the result.")
    }

    return textResult(String(decoding: data, as: UTF8.self))
}
