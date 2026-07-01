//
//  ReadOnlyEnvironment.swift
//  BuddyDesignSystem
//
//  The shared `isReadOnly` environment flag, lifted from the coderpad app so the
//  design system's editing controls (the inline-editable title) can gate themselves
//  on it without the app injecting a bespoke key. Both apps drive it the same way —
//  set once at the window root when the app goes read-only (e.g. offline) — so
//  editing controls disable themselves rather than firing a mutation against an
//  unreachable server.
//

import SwiftUI

extension EnvironmentValues {
    /// True while the surrounding UI is read-only (e.g. the app is offline). Editing
    /// controls read this to disable themselves so a browse-only state never lets a
    /// mutation fire. Injected once at the window root by the app; defaults to `false`
    /// (editable).
    @Entry public var isReadOnly: Bool = false
}
