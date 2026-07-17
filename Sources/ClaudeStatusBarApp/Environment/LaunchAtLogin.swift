import Foundation
import ServiceManagement

public enum LaunchAtLogin {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    public static func setEnabled(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { /* surfaced via the toggle reverting on next read */ }
    }
}
