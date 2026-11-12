# buddy-kit

The service-agnostic shared foundation for the "buddy" family of macOS apps: [PadBuddy](https://github.com/adamtheturtle/coderpad-macos) (for CoderPad) and RankBuddy (for HackerRank).
Every product here is domain-free, so a sibling app can consume it unchanged.

## Products

| Product | What it holds |
| --- | --- |
| `BuddyDesignSystem` | Generic SwiftUI primitives: colour/spacing tokens, reusable cards / section headers / stat tiles / chips / avatars, the `FilterChipMenu` family, `FilterableListView`, the `PopoverSelectionRow` picker row, the `CredentialValidationState` + `ValidationStatusBanner` account-validation pair, and the cross-platform `Platform*` bridge. |
| `BuddyAppKit` | Zero-coupling app utilities: pasteboard, URL opening, reachability, a relative-date cache, multi-selection rules, a serial write queue, a lenient array decoder, a generic Keychain account store, the `DateWindow`/`NamedDateRange` list-filter primitives with the `ListFilterCriteria` seam, a `RevisionMemo` recompute-on-signature-change cache, the iCloud `CloudSyncMerge` strategies + `CloudSyncStore` key-value mirror, and the `AccountScoped` merged-row type + `MergedLoader` per-account fan-out. |
| `BuddySparkleUpdater` | Optional Sparkle-backed update UI for direct distribution builds. Keep this out of Mac App Store targets. |

`BuddySparkleUpdater` depends on `BuddyAppKit`.
The dependency graph is acyclic.

## Requirements

- macOS 15+
- Swift 6 language mode, MainActor default actor isolation to match the consuming app targets.

## Build & test

```sh
swift build
swift test
```

## Consuming this package

```swift
.package(url: "https://github.com/adamtheturtle/buddy-kit", from: "0.1.0")
```

Then add the products you need (`BuddyDesignSystem`, `BuddyAppKit`, `BuddySparkleUpdater`) to your target's dependencies.
