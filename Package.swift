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

/// buddy-kit: the service-agnostic shared foundation for the "buddy" family of
/// macOS apps (PadBuddy for CoderPad, RankBuddy for HackerRank). Each product is
/// domain-free so a sibling app can consume it unchanged:
///
/// - `BuddyDesignSystem` — generic SwiftUI primitives: colour/spacing tokens, the
///   reusable cards/section-headers/stat-tiles/chips/avatars, the `FilterChipMenu`
///   family, `FilterableListView`, the `PopoverSelectionRow` picker row, the
///   `CredentialValidationState` + `ValidationStatusBanner` account-validation pair, the
///   cross-platform `Platform*` bridge, the `printDocument` print/Save-as-PDF core with
///   its `PrintSection`/`PrintCode` primitives, and the `macPullToRefresh` bridge.
///   (The NSTableView-backed list now lives in the standalone FastList package:
///   https://github.com/adamtheturtle/FastList.)
/// - `BuddyAppKit` — zero-coupling app utilities (pasteboard, URL opening,
///   reachability, a relative-date cache, multi-selection rules, a serial write
///   queue, a lenient array decoder, a generic Keychain account store, the
///   `DateWindow`/`NamedDateRange` list-filter primitives plus the `ListFilterCriteria`
///   seam, a `RevisionMemo` recompute-on-signature-change cache, the iCloud
///   `CloudSyncMerge` strategies + `CloudSyncStore` key-value mirror, the
///   `AccountScoped` merged-row type + `MergedLoader` per-account fan-out, and the
///   `RefreshSchedule`/`periodicReload` wall-clock refresh loop).
///
/// Settings mirror the consuming app targets so the sources compile identically:
/// Swift 6 language mode and MainActor default actor isolation, against which the
/// files' `nonisolated` annotations are written. macOS 15+.
///
/// The MCP server scaffolding that lived here (`BuddyMCP`) now ships as the standalone
/// MCPKit package: https://github.com/adamtheturtle/MCPKit
///
/// The library products are independent (no inter-product dependencies); the DAG is
/// deliberately acyclic.
let package = Package(
    name: "buddy-kit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "BuddyDesignSystem", targets: ["BuddyDesignSystem"]),
        .library(name: "BuddyAppKit", targets: ["BuddyAppKit"])
    ],
    dependencies: [
        // Backs the reusable `FlowLayout` wrapper. Pinned to the same major the apps
        // use so everything resolves to one Flow version.
        .package(url: "https://github.com/tevelee/SwiftUI-Flow", from: "3.4.0"),
        // Backs the reusable `MarkdownText` view. Pinned to the exact version the apps
        // use so everything resolves to one Textual revision.
        .package(url: "https://github.com/adamtheturtle/textual", exact: "0.5.1")
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
        )
    ]
)
