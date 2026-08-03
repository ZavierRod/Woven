import SwiftUI

private enum WovenVaultDestination: Hashable {
    case privateVault
    case pairVault
}

struct WovenVaultHomeView: View {
    let soloVaultStore: SoloVaultStore
    let pairVaultStore: PairVaultStore
    var session: PairSession?
    var onSignOut: (() -> Void)?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                WovenTheme.background.ignoresSafeArea()

                RadialGradient(
                    colors: [WovenTheme.accent.opacity(0.09), .clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 420
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: WovenTheme.spacing32) {
                        header

                        VStack(spacing: WovenTheme.spacing16) {
                            NavigationLink(value: WovenVaultDestination.privateVault) {
                                vaultCard(
                                    eyebrow: "JUST FOR YOU",
                                    title: soloTitle,
                                    detail: soloDetail,
                                    symbol: "person.crop.circle",
                                    gradient: WovenTheme.soloVaultGradient
                                )
                            }
                            .accessibilityLabel("Open private Solo vault, \(soloDetail)")

                            NavigationLink(value: WovenVaultDestination.pairVault) {
                                vaultCard(
                                    eyebrow: "OPEN TOGETHER",
                                    title: pairTitle,
                                    detail: pairDetail,
                                    symbol: "person.2",
                                    gradient: WovenTheme.sharedVaultGradient
                                )
                            }
                            .accessibilityLabel("Open Pair vault, \(pairDetail)")
                        }
                        .buttonStyle(.plain)

                        Label(
                            "Photos are encrypted before they leave your hands.",
                            systemImage: "lock.shield"
                        )
                        .font(WovenTheme.footnote())
                        .foregroundStyle(WovenTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, WovenTheme.spacing8)
                    }
                    .padding(.horizontal, WovenTheme.spacing20)
                    .padding(.top, WovenTheme.spacing24)
                    .padding(.bottom, WovenTheme.spacing32)
                }
            }
            .navigationTitle("Vaults")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(WovenTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if let session, let onSignOut {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Section {
                                Text(session.fullName ?? session.username)
                                Text(session.email)
                            }
                            Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                onSignOut()
                            }
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(WovenTheme.accent)
                        }
                        .accessibilityLabel("Account and sign out")
                    }
                }
            }
            .navigationDestination(for: WovenVaultDestination.self) { destination in
                switch destination {
                case .privateVault:
                    SoloVaultRootView(store: soloVaultStore, includesNavigationStack: false)
                case .pairVault:
                    PairVaultRootView(store: pairVaultStore, includesNavigationStack: false)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await soloVaultStore.bootstrap()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else { return }
            soloVaultStore.lock()
            pairVaultStore.lock()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: WovenTheme.spacing16) {
            WovenMark(size: 52)

            VStack(alignment: .leading, spacing: WovenTheme.spacing8) {
                Text("WOVEN")
                    .font(.caption.weight(.semibold))
                    .tracking(2.8)
                    .foregroundStyle(WovenTheme.accent)
                Text("Your private spaces")
                    .font(.system(.title, design: .serif, weight: .semibold))
                    .foregroundStyle(WovenTheme.textPrimary)
                Text("Keep something for yourself, or hold it together with someone you trust.")
                    .font(WovenTheme.subheadline())
                    .foregroundStyle(WovenTheme.textSecondary)
                    .lineSpacing(2)
            }
        }
    }

    private func vaultCard(
        eyebrow: String,
        title: String,
        detail: String,
        symbol: String,
        gradient: LinearGradient
    ) -> some View {
        VStack(alignment: .leading, spacing: WovenTheme.spacing24) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(WovenTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(WovenTheme.accentSoft, in: Circle())
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WovenTheme.textTertiary)
            }

            VStack(alignment: .leading, spacing: WovenTheme.spacing8) {
                Text(eyebrow)
                    .font(.caption2.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(WovenTheme.accent)
                Text(title)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(WovenTheme.textPrimary)
                Text(detail)
                    .font(WovenTheme.subheadline())
                    .foregroundStyle(WovenTheme.textSecondary)
            }
        }
        .padding(WovenTheme.spacing24)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .background(gradient, in: RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusCard, style: .continuous)
                .stroke(WovenTheme.textPrimary.opacity(0.08), lineWidth: 1)
        }
    }

    private var soloTitle: String {
        switch soloVaultStore.phase {
        case .locked(let summary): summary.name
        case .unlocked(let manifest): manifest.name
        default: "Private Vault"
        }
    }

    private var soloDetail: String {
        switch soloVaultStore.phase {
        case .loading: "Preparing your private space…"
        case .noVault: "Create a vault that stays on this device"
        case .locked(let summary): photoCount(summary.photoCount, suffix: "inside · Locked")
        case .unlocked(let manifest): photoCount(manifest.media.count, suffix: "inside · Open")
        case .failed: "Needs your attention"
        }
    }

    private var pairTitle: String {
        switch pairVaultStore.phase {
        case .unlocked(_, let name): name
        default: "Pair Vault"
        }
    }

    private var pairDetail: String {
        switch pairVaultStore.phase {
        case .signedOut, .loading: "Preparing your shared space…"
        case .ready: "Create a space with someone you trust"
        case .invitation: "An invitation is waiting for you"
        case .waitingForPartner: "Waiting for your partner to join"
        case .locked: "Ready when you both are · Locked"
        case .unlocked: photoCount(pairVaultStore.decryptedMedia.count, suffix: "inside · Open")
        case .failed: "Needs your attention"
        }
    }

    private func photoCount(_ count: Int, suffix: String) -> String {
        let noun = count == 1 ? "photo" : "photos"
        return "\(count) \(noun) \(suffix)"
    }
}
