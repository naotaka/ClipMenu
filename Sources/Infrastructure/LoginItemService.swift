import ServiceManagement

/// Manages launch-at-login registration via `SMAppService`.
///
/// Replaces the legacy Carbon `LSSharedFileList` approach in
/// `legacy/Source/NaoAdditions/LoginItems.m`.
final class LoginItemService {

    private let service = SMAppService.mainApp

    var isEnabled: Bool {
        service.status == .enabled
    }

    func enable() throws {
        try service.register()
    }

    func disable() throws {
        try service.unregister()
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try enable()
        } else {
            try disable()
        }
    }
}
