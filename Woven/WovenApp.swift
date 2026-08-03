import SwiftUI

@main
struct WovenApp: App {
    private let configuration: Result<AppConfiguration, Error>

    init() {
        configuration = Result { try AppConfiguration.load() }
    }

    var body: some Scene {
        WindowGroup {
            switch configuration {
            case .success(let configuration):
                #if WOVEN_DEVELOPMENT_AUTH
                if configuration.permitsDevelopmentAccounts {
                    DevelopmentRootView()
                } else {
                    ProductionRootView(configuration: configuration)
                }
                #else
                ProductionRootView(configuration: configuration)
                #endif
            case .failure(let error):
                ConfigurationErrorView(message: error.localizedDescription)
            }
        }
    }
}

#if WOVEN_DEVELOPMENT_AUTH
private struct DevelopmentRootView: View {
    @State private var soloVaultStore = SoloVaultStore()
    @State private var pairVaultStore = PairVaultStore()

    var body: some View {
        WovenVaultHomeView(soloVaultStore: soloVaultStore, pairVaultStore: pairVaultStore)
    }
}
#endif

private struct ProductionRootView: View {
    private let configuration: AppConfiguration
    @State private var authentication: ProductionAuthenticationStore
    @State private var soloVaultStore = SoloVaultStore()
    @State private var pairVaultStore = PairVaultStore()

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        _authentication = State(initialValue: ProductionAuthenticationStore(configuration: configuration))
    }

    var body: some View {
        Group {
            if let session = authentication.session {
                WovenVaultHomeView(
                    soloVaultStore: soloVaultStore,
                    pairVaultStore: pairVaultStore,
                    session: session,
                    onSignOut: { Task { await authentication.signOut() } }
                )
                    .task(id: session.accessToken) {
                        await pairVaultStore.signIn(session: session)
                    }
            } else {
                ProductionSignInView(store: authentication)
                    .task { await authentication.restore() }
            }
        }
        .overlay(alignment: .top) {
            if configuration.environment == .staging {
                Text("STAGING")
                    .font(.caption2.bold())
                    .tracking(1.2)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .foregroundStyle(WovenTheme.accent)
                    .background(WovenTheme.cardBackground, in: Capsule())
                    .overlay {
                        Capsule().stroke(WovenTheme.accent.opacity(0.45), lineWidth: 1)
                    }
                    .padding(.top, 8)
                    .accessibilityLabel("Woven staging build")
                    .allowsHitTesting(false)
            }
        }
    }
}
