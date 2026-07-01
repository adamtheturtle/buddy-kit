//
//  LoginItem.swift
//  BuddyAppKit
//
//  A thin wrapper over `SMAppService.mainApp` for the "Launch at login" setting
//  (#641). The system, not `UserDefaults`, is the source of truth: `isEnabled` reads
//  the live registration status, and a Settings toggle mirrors it. Registering /
//  unregistering can throw, so the caller surfaces the error and reflects the real
//  state rather than assuming the change took. Lifted from the coderpad app; wrapped in
//  `#if os(macOS)` with iOS no-ops (there's no launch-at-login concept on iOS) so the
//  settings call sites keep compiling everywhere.
//

#if os(macOS)
    import ServiceManagement
#endif

public enum LoginItem {
    /// Whether the app is currently registered to launch at login. Always `false` on
    /// iOS, which has no launch-at-login concept.
    public static var isEnabled: Bool {
        #if os(macOS)
            SMAppService.mainApp.status == .enabled
        #else
            false
        #endif
    }

    /// Registers or unregisters the app as a login item. Throws if the system rejects
    /// the change (e.g. the user disabled it in System Settings -> General -> Login
    /// Items). A no-op on iOS.
    public static func setEnabled(_ enabled: Bool) throws {
        #if os(macOS)
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        #else
            _ = enabled
        #endif
    }
}
