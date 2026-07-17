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
                if configuration.permitsDevelopmentAccounts {
                    DevelopmentRootView()
                } else {
                    ProductionRootView(configuration: configuration)
                }
            case .failure(let error):
                ConfigurationErrorView(message: error.localizedDescription)
            }
        }
    }
}

private struct DevelopmentRootView: View {
    @State private var soloVaultStore = SoloVaultStore()
    @State private var pairVaultStore = PairVaultStore()

    var body: some View {
        WovenVaultTabs(soloVaultStore: soloVaultStore, pairVaultStore: pairVaultStore)
    }
}

private struct ProductionRootView: View {
    @State private var authentication: ProductionAuthenticationStore
    @State private var soloVaultStore = SoloVaultStore()
    @State private var pairVaultStore = PairVaultStore()

    init(configuration: AppConfiguration) {
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
