// swift-tools-version: 6.2
import PackageDescription

/// Shared per-target Swift settings, mirroring the consuming app targets so moved
/// source compiles identically: Swift 6 language mode, MainActor default isolation,
/// and the app's SWIFT_APPROACHABLE_CONCURRENCY = YES upcoming features. Declared
/// before `package` so it is in scope where the targets reference it.
let buddySwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances")
]

/// `BuddyMCP` deliberately does NOT take MainActor default isolation: the MCP server is
/// actor-based and its method handlers are nonisolated `@Sendable` closures, so the code
/// is written against the default (nonisolated) isolation the official SDK expects -
/// mirroring the standalone `coderpad-mcp` package, which isolates nothing.
let mcpSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
]

/// buddy-kit: the service-agnostic shared foundation for the "buddy" family of
/// macOS apps (PadBuddy for CoderPad, RankBuddy for HackerRank). Each product is
/// domain-free so a sibling app can consume it unchanged:
///
/// - `BuddyDesignSystem` — generic SwiftUI primitives: colour/spacing tokens, the
///   reusable cards/section-headers/stat-tiles/chips/avatars, the `FilterChipMenu`
///   family, and `FilterableListView`. (The NSTableView-backed list now lives in the
///   standalone FastList package: https://github.com/adamtheturtle/FastList.)
/// - `BuddyAppKit` — zero-coupling app utilities (pasteboard, URL opening,
///   reachability, a relative-date cache, multi-selection rules, a serial write
///   queue, a lenient array decoder, a generic Keychain account store, the
///   `DateWindow`/`NamedDateRange` list-filter primitives plus the `ListFilterCriteria`
///   seam, a `RevisionMemo` recompute-on-signature-change cache, and the iCloud
///   `CloudSyncMerge` strategies + `CloudSyncStore` key-value mirror).
///
/// Settings mirror the consuming app targets so the sources compile identically:
/// Swift 6 language mode and MainActor default actor isolation, against which the
/// files' `nonisolated` annotations are written. macOS 15+.
///
/// - `BuddyMCP` — a service-agnostic seam over the official MCP Swift SDK: an
///   `MCPToolProvider` protocol a host app implements with its own tool catalog and
///   dispatch, plus a `BuddyMCPServer` bootstrap that wires the provider to the SDK and
///   runs it over a transport, with generic argument-coercion / descriptor-to-`Tool` /
///   result-builder scaffolding. The concrete catalog, transforms, prompts, resources
///   and account model stay app-side.
///
/// The library products are independent (no inter-product dependencies); the DAG is
/// deliberately acyclic. `BuddyMCP` depends only on Foundation + the MCP SDK.
let package = Package(
    name: "buddy-kit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "BuddyDesignSystem", targets: ["BuddyDesignSystem"]),
        .library(name: "BuddyAppKit", targets: ["BuddyAppKit"]),
        .library(name: "BuddyMCP", targets: ["BuddyMCP"])
    ],
    dependencies: [
        // Backs the reusable `FlowLayout` wrapper. Pinned to the same major the apps
        // use so everything resolves to one Flow version.
        .package(url: "https://github.com/tevelee/SwiftUI-Flow", from: "3.4.0"),
        // Backs the reusable `MarkdownText` view. Pinned to the exact version the apps
        // use so everything resolves to one Textual revision.
        .package(url: "https://github.com/adamtheturtle/textual", exact: "0.5.1"),
        // The official Model Context Protocol Swift SDK, backing `BuddyMCP`. Pinned to
        // the same major the apps' MCP servers use so everything resolves to one version.
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1")
    ],
    targets: [
        .target(
            name: "BuddyDesignSystem",
            dependencies: [
                .product(name: "Flow", package: "SwiftUI-Flow"),
                .product(name: "Textual", package: "textual")
            ],
            swiftSettings: buddySwiftSettings
        ),
        .testTarget(
            name: "BuddyDesignSystemTests",
            dependencies: ["BuddyDesignSystem"],
            swiftSettings: buddySwiftSettings
        ),
        .target(
            name: "BuddyAppKit",
            swiftSettings: buddySwiftSettings
        ),
        .testTarget(
            name: "BuddyAppKitTests",
            dependencies: ["BuddyAppKit"],
            swiftSettings: buddySwiftSettings
        ),
        .target(
            name: "BuddyMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            swiftSettings: mcpSwiftSettings
        ),
        .testTarget(
            name: "BuddyMCPTests",
            dependencies: ["BuddyMCP"],
            swiftSettings: mcpSwiftSettings
        )
    ]
)
