//
//  LanguageCatalog.swift
//  BuddyAppKit
//
//  A language-code -> display-name table shared by the interview apps (#640), so the
//  same raw API codes (`cpp`, `py`, `node`, ...) read identically across them. The two
//  apps' hand-rolled tables are reconciled here into one superset; unknown codes fall
//  back to a title-cased version of the code itself.
//
//  DISPLAY NAMES ONLY. Anything service-branded (link tables, per-language URLs, the
//  picker's option order, or an app's project/multi-file environment semantics) stays
//  app-side — this is a pure, `nonisolated` lookup safe to call during off-main decode
//  or export.
//

import Foundation

public extension String {
    /// A human-friendly display name for a language code (e.g. `"cpp"` -> `"C++"`,
    /// `"python"` -> `"Python"`, `"node"` -> `"Node.js"`). Matching is case-insensitive
    /// and covers common aliases. An unknown, non-empty code is title-cased as a
    /// sensible fallback; an empty string is returned unchanged.
    ///
    /// `nonisolated` (pure) so off-main callers such as JSON decoders and CSV export can
    /// use it even though `BuddyAppKit`'s default isolation is `MainActor`.
    nonisolated var languageDisplayName: String {
        if let name = LanguageCatalog.displayNames[lowercased()] { return name }

        return isEmpty ? self : prefix(1).uppercased() + dropFirst()
    }
}

/// The reconciled language-code -> display-name table backing ``Swift/String/languageDisplayName``.
/// Exposed so callers that hold a code (not a `String` value) can look up directly.
public enum LanguageCatalog {
    /// Canonical display names keyed by lower-cased code, including common aliases. A
    /// table rather than a `switch` so the lookup stays a single low-complexity
    /// expression. Superset of both apps' tables.
    public nonisolated static let displayNames: [String: String] = [
        "python": "Python", "py": "Python",
        "python2": "Python 2", "python3": "Python 3",
        "javascript": "JavaScript", "js": "JavaScript",
        "typescript": "TypeScript", "ts": "TypeScript",
        "node": "Node.js", "node.js": "Node.js", "nodejs": "Node.js",
        "swift": "Swift",
        "go": "Go", "golang": "Go",
        "rust": "Rust",
        "java": "Java", "kotlin": "Kotlin",
        "ruby": "Ruby",
        "c": "C", "cpp": "C++", "c++": "C++",
        "csharp": "C#", "c#": "C#",
        "objective-c": "Objective-C", "objc": "Objective-C",
        "php": "PHP", "html": "HTML", "css": "CSS", "sql": "SQL",
        "mysql": "MySQL", "postgresql": "PostgreSQL", "postgres": "PostgreSQL",
        "bash": "Bash", "shell": "Shell", "sh": "Shell",
        "r": "R", "scala": "Scala",
        "elixir": "Elixir", "erlang": "Erlang", "haskell": "Haskell",
        "perl": "Perl", "lua": "Lua", "dart": "Dart",
        "clojure": "Clojure", "ocaml": "OCaml",
        "f#": "F#", "fsharp": "F#",
        "julia": "Julia", "markdown": "Markdown", "solidity": "Solidity",
        "tcl": "Tcl", "verilog": "Verilog"
    ]
}
