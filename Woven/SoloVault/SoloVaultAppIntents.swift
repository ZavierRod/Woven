import AppIntents

struct OpenSoloVaultIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Solo Vault"
    static var description = IntentDescription("Open Woven to your local Solo vault.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct WovenAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSoloVaultIntent(),
            phrases: [
                "Open my vault in \(.applicationName)",
                "Open \(.applicationName)"
            ],
            shortTitle: "Open Solo Vault",
            systemImageName: "lock.shield.fill"
        )
    }
}

