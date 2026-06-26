# buddy-kit

The service-agnostic shared foundation for the "buddy" family of macOS apps:
[PadBuddy](https://github.com/adamtheturtle/coderpad-macos) (for CoderPad) and
RankBuddy (for HackerRank). Every product here is domain-free, so a sibling app can
consume it unchanged.

## Products

| Product | What it holds |
| --- | --- |
| `BuddyDesignSystem` | Generic SwiftUI primitives: colour/spacing tokens, reusable cards / section headers / stat tiles / chips / avatars, the `FilterChipMenu` family, `FilterableListView`, the `PopoverSelectionRow` picker row, the `CredentialValidationState` + `ValidationStatusBanner` account-validation pair, the cross-platform `Platform*` bridge, the `printDocument` print/Save-as-PDF core (`PrintSection`/`PrintCode`), and the `macPullToRefresh` bridge. (The NSTableView-backed list lives in the standalone [FastList](https://github.com/adamtheturtle/FastList) package.) |
| `BuddyAppKit` | Zero-coupling app utilities: pasteboard, URL opening, reachability, a relative-date cache, multi-selection rules, a serial write queue, a lenient array decoder, a generic Keychain account store, the `DateWindow`/`NamedDateRange` list-filter primitives with the `ListFilterCriteria` seam, a `RevisionMemo` recompute-on-signature-change cache, the iCloud `CloudSyncMerge` strategies + `CloudSyncStore` key-value mirror, the `AccountScoped` merged-row type + `MergedLoader` per-account fan-out, and the `RefreshSchedule`/`periodicReload` wall-clock refresh loop. |
| `BuddyMCP` | A service-agnostic seam over the official MCP Swift SDK: an `MCPToolProvider` protocol a host app implements with its own tool catalog and dispatch, plus a `BuddyMCPServer` bootstrap that wires it to the SDK and runs it over a transport, with generic argument-coercion / descriptor-to-`Tool` / result-builder scaffolding. |

The library products are independent — there are no inter-product dependencies, and the
dependency graph is deliberately acyclic. `BuddyMCP` depends only on Foundation and the
MCP SDK; the others carry no MCP dependency.

## Requirements

- macOS 15+
- Swift 6 language mode, MainActor default actor isolation (mirrors the consuming app
  targets so moved source compiles identically).

## Build & test

```sh
swift build
swift test
```

## Consuming this package

```swift
.package(url: "https://github.com/adamtheturtle/buddy-kit", from: "0.1.0")
```

Then add the products you need (`BuddyDesignSystem`, `PaginatedRESTClient`,
`BuddyAppKit`) to your target's dependencies.
