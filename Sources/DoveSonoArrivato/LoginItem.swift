import ServiceManagement

// Opening at login through the system's Login Items, so the panel is there after a restart.
@MainActor
enum LoginItem {
    static let configuredKey = "launchAtLoginConfigured"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status != .notRegistered else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    // On by default, once: turning it off in Settings is respected afterwards.
    static func enableByDefaultOnce() {
        guard !UserDefaults.standard.bool(forKey: configuredKey) else { return }
        UserDefaults.standard.set(true, forKey: configuredKey)
        do { try set(true) } catch { NSLog("Login item unavailable: %@", error.localizedDescription) }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
