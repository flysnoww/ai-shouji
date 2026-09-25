import Foundation

struct FireseedUser: Codable, Equatable, Sendable {
    let stableUserID: String
    let email: String?
    let displayName: String?
}

enum IdentityState: Equatable {
    case resolving
    case signedOut
    case signedIn(FireseedUser)
}

@MainActor protocol IdentityProvider: AnyObject {
    func restoreSession() async throws -> FireseedUser?
    func signIn() async throws -> FireseedUser
    func signOut() async throws
}

@MainActor final class MockAuthProvider: IdentityProvider {
    static let sessionKey = "fireseed.identity.mock.userID"

    private static let users = [
        FireseedUser(stableUserID: "fireseed-mock-user-a", email: "test1@example.invalid", displayName: "Test User 1"),
        FireseedUser(stableUserID: "fireseed-mock-user-b", email: "test2@example.invalid", displayName: "Test User 2")
    ]

    private let user: FireseedUser
    private let defaults: UserDefaults

    init(account: Int = 1, defaults: UserDefaults = .standard) {
        user = Self.users[account == 2 ? 1 : 0]
        self.defaults = defaults
    }

    func restoreSession() async throws -> FireseedUser? {
        try Task.checkCancellation()
        guard let savedID = defaults.string(forKey: Self.sessionKey) else { return nil }
        return Self.users.first { $0.stableUserID == savedID }
    }

    func signIn() async throws -> FireseedUser {
        try Task.checkCancellation()
        try Task.checkCancellation()
        defaults.set(user.stableUserID, forKey: Self.sessionKey)
        return user
    }

    func signOut() async throws {
        try Task.checkCancellation()
        defaults.removeObject(forKey: Self.sessionKey)
    }
}
