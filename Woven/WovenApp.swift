import SwiftUI

@main
struct WovenApp: App {
    @State private var soloVaultStore = SoloVaultStore()
    @State private var pairVaultStore = PairVaultStore()

    var body: some Scene {
        WindowGroup {
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
}
