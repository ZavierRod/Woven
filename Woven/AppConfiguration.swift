import Foundation

enum WovenEnvironment: String, Sendable {
    case local
    case test
    case staging
    case production
}

enum AppConfigurationError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

struct AppConfiguration: Sendable {
    let environment: WovenEnvironment
    let apiBaseURL: URL

    static func load(bundle: Bundle = .main) throws -> Self {
        guard let rawEnvironment = bundle.object(forInfoDictionaryKey: "WOVEN_ENVIRONMENT") as? String,
              let environment = WovenEnvironment(rawValue: rawEnvironment.lowercased()) else {
            throw AppConfigurationError.invalid("WOVEN_ENVIRONMENT must be local, test, staging, or production.")
        }
        guard let rawURL = bundle.object(forInfoDictionaryKey: "WOVEN_API_BASE_URL") as? String,
              !rawURL.isEmpty,
              !rawURL.contains("$("),
              let url = URL(string: rawURL),
              let host = url.host else {
            throw AppConfigurationError.invalid("WOVEN_API_BASE_URL must be an absolute URL.")
        }

        let localHosts = ["localhost", "127.0.0.1", "::1"]
        switch environment {
        case .local, .test:
            #if !DEBUG
            throw AppConfigurationError.invalid("Local and test environments are unavailable in Release builds.")
            #else
            guard url.scheme == "http" || url.scheme == "https" else {
                throw AppConfigurationError.invalid("Local API URL must use HTTP or HTTPS.")
            }
            #endif
        case .staging, .production:
            guard url.scheme == "https", !localHosts.contains(host) else {
                throw AppConfigurationError.invalid("Staging and production require a non-local HTTPS API URL.")
            }
        }
        return Self(environment: environment, apiBaseURL: url)
    }

    var permitsDevelopmentAccounts: Bool {
        #if WOVEN_DEVELOPMENT_AUTH
        environment == .local || environment == .test
        #else
        false
        #endif
    }

    static var configuredBaseURLString: String {
        (try? load().apiBaseURL.absoluteString) ?? "woven-invalid://configuration"
    }
}
