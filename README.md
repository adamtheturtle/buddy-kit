# buddy-kit

The service-agnostic shared foundation for the "buddy" family of macOS apps:
[PadBuddy](https://github.com/adamtheturtle/coderpad-macos) (for CoderPad) and
RankBuddy (for HackerRank). Every product here is domain-free, so a sibling app can
consume it unchanged.

## Products

| Product | What it holds |
| --- | --- |
| `BuddyDesignSystem` | Generic SwiftUI primitives: colour/spacing tokens, reusable cards / section headers / stat tiles / chips / avatars, the `FilterChipMenu` family, `FilterableListView`, and the NSTableView-backed `ListTable`. |
| `PaginatedRESTClient` | A generic transport for paginated, bearer-authenticated REST APIs. |
| `BuddyAppKit` | Zero-coupling app utilities: pasteboard, URL opening, reachability, a relative-date cache, multi-selection rules, a serial write queue, a lenient array decoder, and a generic Keychain account store. |

The three products are independent — there are no inter-product dependencies, and the
dependency graph is deliberately acyclic so a future Foundation-only MCP product can be
added without a cycle.

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
