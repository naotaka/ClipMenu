import SwiftUI

// MARK: - ClipsService

private struct ClipsServiceKey: EnvironmentKey {
    static let defaultValue: ClipsService = AppRuntime.shared.clipsService
}

extension EnvironmentValues {
    var clipsService: ClipsService {
        get { self[ClipsServiceKey.self] }
        set { self[ClipsServiceKey.self] = newValue }
    }
}

// MARK: - SnippetService

private struct SnippetServiceKey: EnvironmentKey {
    static let defaultValue: SnippetService = SnippetService()
}

extension EnvironmentValues {
    var snippetService: SnippetService {
        get { self[SnippetServiceKey.self] }
        set { self[SnippetServiceKey.self] = newValue }
    }
}

// MARK: - ActionService

private struct ActionServiceKey: EnvironmentKey {
    static let defaultValue: ActionService = ActionService()
}

extension EnvironmentValues {
    var actionService: ActionService {
        get { self[ActionServiceKey.self] }
        set { self[ActionServiceKey.self] = newValue }
    }
}

// MARK: - LoginItemService

private struct LoginItemServiceKey: EnvironmentKey {
    static let defaultValue: LoginItemService = LoginItemService()
}

extension EnvironmentValues {
    var loginItemService: LoginItemService {
        get { self[LoginItemServiceKey.self] }
        set { self[LoginItemServiceKey.self] = newValue }
    }
}
