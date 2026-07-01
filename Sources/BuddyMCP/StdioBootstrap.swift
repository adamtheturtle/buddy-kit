//
//  StdioBootstrap.swift
//  BuddyMCP
//
//  The stdio entry-point bootstrap every host app hand-rolled around `BuddyMCPServer`
//  (#647). When a host binary is launched with `--mcp` it must NOT start its UI: it
//  speaks MCP over stdio, so its synchronous `main` needs to bridge to the async server
//  and never return. Both PadBuddy and RankBuddy wrote the same control flow - detect the
//  flag, read the bundle version, build the server, run it over `StdioTransport`, and
//  block the calling thread on a `DispatchSemaphore` until the transport closes, logging
//  any failure to standard error. This lifts that shared shape here.
//
//  What stays app-side is passed in as closures: the enabled-gate check and any launch
//  side effect (PadBuddy's activity-log launch record) are service-specific, so
//  `isEnabled` and `onLaunch` are supplied by the caller rather than baked in.
//

import Foundation
import MCP

public extension BuddyMCPServer {
    /// The conventional command-line flag that switches a host binary into headless MCP
    /// mode. A host's `main` checks `wantsStdioMCP(_:)` (or this literal) before starting
    /// its UI.
    static let stdioModeFlag = "--mcp"

    /// Whether `arguments` (typically `CommandLine.arguments`) requests headless MCP mode,
    /// i.e. contains the `--mcp` flag past the executable path.
    static func wantsStdioMCP(_ arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.dropFirst().contains(stdioModeFlag)
    }

    /// The version to report in the MCP `initialize` handshake's `serverInfo`, read from
    /// the app bundle's `CFBundleShortVersionString`, defaulting to `"1.0"`.
    static var bundleShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Serves `provider` over stdio until the client disconnects, then exits the process -
    /// the all-in-one entry a host's `main` calls once it has decided (via
    /// `wantsStdioMCP(_:)`) that it's in MCP mode. It never returns.
    ///
    /// The two service-specific decisions are supplied as closures so this stays
    /// service-agnostic:
    /// - `isEnabled` is consulted first; when it returns `false` the server is not started,
    ///   `disabledMessage` (if any) is written to standard error, and the process exits with
    ///   `EXIT_FAILURE`. Pass a closure returning `true` (the default) to always serve.
    /// - `onLaunch` runs once, just before serving, for a launch side effect such as
    ///   recording the launch in an activity log. Defaults to a no-op.
    ///
    /// Failures starting or running the server are logged to standard error (prefixed with
    /// `name`) and the process still exits cleanly, matching the prior hand-rolled behaviour.
    ///
    /// - Parameters:
    ///   - name: The server identity for `serverInfo` and error-log prefixing.
    ///   - version: The version for `serverInfo`. Defaults to `bundleShortVersion`.
    ///   - capabilities: Advertised capabilities. Defaults to tools-only, as both in-app
    ///     servers are.
    ///   - isEnabled: The app's enabled-gate check, run before serving. Defaults to `true`.
    ///   - disabledMessage: Written to standard error when `isEnabled` returns `false`.
    ///   - onLaunch: A launch side effect run just before serving. Defaults to a no-op.
    ///   - provider: The service's tool provider.
    static func runOverStdioUntilExit(
        name: String,
        version: String = bundleShortVersion,
        capabilities: Server.Capabilities = .init(tools: .init(listChanged: false)),
        isEnabled: @Sendable () -> Bool = { true },
        disabledMessage: String? = nil,
        onLaunch: @Sendable () -> Void = {},
        provider: any MCPToolProvider
    ) -> Never {
        guard isEnabled() else {
            if let disabledMessage {
                FileHandle.standardError.write(Data((disabledMessage + "\n").utf8))
            }
            exit(EXIT_FAILURE)
        }

        onLaunch()

        // Bridge the SDK's async server to this synchronous, never-returning entry point.
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let server = BuddyMCPServer(
                name: name,
                version: version,
                capabilities: capabilities,
                provider: provider
            )
            do {
                try await server.run(transport: StdioTransport())
            } catch {
                FileHandle.standardError.write(Data("\(name) MCP server failed to start: \(error)\n".utf8))
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }
}
