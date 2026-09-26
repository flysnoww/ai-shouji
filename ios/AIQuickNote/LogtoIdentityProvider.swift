import AuthenticationServices
import Foundation
import Logto
import LogtoClient

enum IdentityEnvironment: String {
    case local = "LOCAL"
    case staging = "STAGING"
    case production = "PRODUCTION"
}

struct IdentityProviderConfiguration {
    let environment: IdentityEnvironment
    let issuer: String
    let endpoint: String
    let clientID: String
    let redirectURI: String
    let postLogoutRedirectURI: String

    init?(info: [String: Any]) {
        guard let environment = (info["FireseedIdentityEnvironment"] as? String).flatMap(IdentityEnvironment.init(rawValue:)) else { return nil }
        self.environment = environment
        issuer = (info["FireseedIdentityIssuer"] as? String ?? "").trimmed
        endpoint = (info["FireseedIdentityEndpoint"] as? String ?? "").trimmed
        clientID = (info["FireseedIdentityClientID"] as? String ?? "").trimmed
        redirectURI = (info["FireseedIdentityRedirectURI"] as? String ?? "").trimmed
        postLogoutRedirectURI = (info["FireseedIdentityPostLogoutRedirectURI"] as? String ?? "").trimmed
    }

    var isUsable: Bool {
        guard !clientID.isEmpty,
              let issuerURL = URLComponents(string: issuer),
              let endpointURL = URLComponents(string: endpoint),
              issuerURL.user == nil, issuerURL.password == nil, issuerURL.query == nil, issuerURL.fragment == nil,
              endpointURL.user == nil, endpointURL.password == nil, endpointURL.query == nil, endpointURL.fragment == nil,
              issuerURL.path == "/oidc", endpointURL.path.isEmpty || endpointURL.path == "/",
              issuerURL.scheme == endpointURL.scheme,
              issuerURL.host?.lowercased() == endpointURL.host?.lowercased(),
              issuerURL.port == endpointURL.port,
              let redirect = URLComponents(string: redirectURI),
              let postLogout = URLComponents(string: postLogoutRedirectURI),
              redirect.scheme == "com.fireseed.aiquicknote",
              postLogout.scheme == redirect.scheme,
              redirect.host == "oauth", redirect.path == "/callback",
              postLogout.host == "oauth", postLogout.path == "/signed-out"
        else { return false }

        switch environment {
        case .local:
            return issuerURL.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(issuerURL.host?.lowercased() ?? "")
        case .staging, .production:
            return issuerURL.scheme == "https"
        }
    }

    static func bundle(_ info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> IdentityProviderConfiguration? {
        IdentityProviderConfiguration(info: info)
    }
}

@MainActor final class LogtoIdentityProvider: IdentityProvider {
    private let configuration: IdentityProviderConfiguration?
    private let client: LogtoClient?

    init(configuration: IdentityProviderConfiguration? = .bundle()) {
        self.configuration = configuration
        guard let configuration, configuration.isUsable,
              let logto = try? LogtoConfig(endpoint: configuration.endpoint, appId: configuration.clientID, scopes: [UserScope.email.rawValue]) else {
            client = nil
            return
        }
        client = LogtoClient(useConfig: logto)
    }

    func restoreSession() async throws -> FireseedUser? {
        guard let client, let configuration else { return nil }
        guard client.isAuthenticated else { return nil }
        do {
            _ = try await client.getAccessToken(for: nil)
            guard client.oidcConfig?.issuer == configuration.issuer else { throw IdentityProviderError.authenticationFailed }
            let userInfo = try await client.fetchUserInfo()
            return try Self.user(subject: userInfo.sub, issuer: client.oidcConfig?.issuer, expectedIssuer: configuration.issuer,
                                 email: userInfo.email, emailVerified: userInfo.emailVerified, displayName: userInfo.name)
        } catch let error as IdentityProviderError {
            throw error
        } catch {
            throw IdentityProviderError.authenticationFailed
        }
    }

    func signIn() async throws -> FireseedUser {
        guard let client, let configuration, configuration.isUsable else { throw IdentityProviderError.notConfigured }
        do {
            try await client.signInWithBrowser(redirectUri: configuration.redirectURI)
            try Task.checkCancellation()
            guard client.oidcConfig?.issuer == configuration.issuer else { throw IdentityProviderError.authenticationFailed }
            let claims = try client.getIdTokenClaims()
            return try Self.user(subject: claims.sub, issuer: claims.iss, expectedIssuer: configuration.issuer,
                                 email: claims.email, emailVerified: claims.emailVerified, displayName: claims.name)
        } catch is CancellationError {
            _ = await client.clearCredentials()
            throw CancellationError()
        } catch {
            if Self.isUserCancelled(error) { throw CancellationError() }
            if error is IdentityProviderError { throw error }
            throw IdentityProviderError.authenticationFailed
        }
    }

    func signOut() async throws {
        guard let client else { return }
        guard let result = await client.signOut(postLogoutRedirectUri: configuration?.postLogoutRedirectURI),
              result.type != .unableToRevokeToken else { return }
        throw IdentityProviderError.signOutFailed
    }

    static func user(subject: String, issuer: String?, expectedIssuer: String, email: String?, emailVerified: Bool?, displayName: String?) throws -> FireseedUser {
        guard !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let issuer, issuer == expectedIssuer else { throw IdentityProviderError.authenticationFailed }
        return FireseedUser(stableUserID: subject, issuer: issuer, email: emailVerified == true ? email : nil, displayName: displayName)
    }

    static func isUserCancelled(_ error: Error) -> Bool {
        let wrapped = error as? LogtoClientErrors.SignIn
        let cause = (wrapped?.innerError ?? error) as NSError
        return cause.domain == ASWebAuthenticationSessionError.errorDomain && cause.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
    }
}
