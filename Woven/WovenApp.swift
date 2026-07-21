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
        WovenVaultTabs(soloVaultStore: soloVaultStore, pairVaultStore: pairVaultStore)
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
                WovenVaultTabs(soloVaultStore: soloVaultStore, pairVaultStore: pairVaultStore)
                    .overlay(alignment: .topTrailing) {
                        Button("Sign Out") { Task { await authentication.signOut() } }
                            .buttonStyle(.bordered)
                            .padding()
                    }
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(.black)
                    .background(.yellow, in: Capsule())
                    .padding(.top, 8)
                    .accessibilityLabel("Woven staging build")
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct WovenVaultTabs: View {
    let soloVaultStore: SoloVaultStore
    let pairVaultStore: PairVaultStore

    var body: some View {
        TabView {
            Tab("Solo", systemImage: "person.crop.circle.badge.checkmark") {
                SoloVaultRootView(store: soloVaultStore)
            }
            Tab("Pair", systemImage: "person.2.badge.key.fill") {
                PairVaultRootView(store: pairVaultStore)
            }
        }
        .tint(WovenTheme.accent)
        .preferredColorScheme(.dark)
    }
}
