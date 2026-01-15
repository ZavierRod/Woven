import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var localAuth: LocalAuthenticationManager
    
    var body: some View {
        ZStack {
            WovenTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: WovenTheme.spacing24) {
                        // Profile Card
                        profileCard
                            .padding(.top, WovenTheme.spacing8)
                        
                        // Security Section
                        settingsSection(title: "Security") {
                            SettingsRow(
                                icon: "faceid",
                                title: "Face ID",
                                iconColor: WovenTheme.success
                            ) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(WovenTheme.success)
                            }
                            
                            Divider()
                                .background(WovenTheme.separator)
                            
                            SettingsRow(
                                icon: "lock",
                                title: "Change Passcode",
                                iconColor: WovenTheme.info
                            ) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(WovenTheme.textTertiary)
                            }
                            
                            Divider()
                                .background(WovenTheme.separator)
                            
                            SettingsRow(
                                icon: "timer",
                                title: "Auto-Lock Timer",
                                subtitle: "5 minutes",
                                iconColor: WovenTheme.warning
                            ) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(WovenTheme.textTertiary)
                            }
                        }
                        
                        // Privacy Section
                        settingsSection(title: "Privacy") {
                            SettingsRow(
                                icon: "camera.metering.none",
                                title: "Screenshot Protection",
                                iconColor: Color(hex: "A855F7")
                            ) {
                                Toggle("", isOn: .constant(true))
                                    .tint(WovenTheme.accent)
                            }
                            
                            Divider()
                                .background(WovenTheme.separator)
                            
                            SettingsRow(
                                icon: "record.circle",
                                title: "Screen Recording Detection",
                                iconColor: WovenTheme.error
                            ) {
                                Toggle("", isOn: .constant(true))
                                    .tint(WovenTheme.accent)
                            }
                        }
                        
                        Text("When enabled, the app will lock and notify your partner if a screenshot or screen recording is detected.")
                            .font(WovenTheme.caption())
                            .foregroundColor(WovenTheme.textTertiary)
                            .padding(.horizontal, WovenTheme.spacing4)
                            .padding(.top, -WovenTheme.spacing12)
                        
                        // About Section
                        settingsSection(title: "About") {
                            SettingsRow(
                                icon: "info.circle",
                                title: "Version",
                                iconColor: WovenTheme.textSecondary
                            ) {
                                Text("1.0.0")
                                    .font(WovenTheme.subheadline())
                                    .foregroundColor(WovenTheme.textSecondary)
                            }
                            
                            Divider()
                                .background(WovenTheme.separator)
                            
                            SettingsRow(
                                icon: "hand.raised",
                                title: "Privacy Policy",
                                iconColor: WovenTheme.info
                            ) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(WovenTheme.textTertiary)
                            }
                            
                            Divider()
                                .background(WovenTheme.separator)
                            
                            SettingsRow(
                                icon: "doc.text",
                                title: "Terms of Service",
                                iconColor: WovenTheme.info
                            ) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(WovenTheme.textTertiary)
                            }
                        }
                        
                        // Debug Section
                        settingsSection(title: "Debug") {
                            NavigationLink(destination: PushDebugView()) {
                                SettingsRow(
                                    icon: "ant",
                                    title: "Push Notifications",
                                    iconColor: .orange
                                ) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(WovenTheme.textTertiary)
                                }
                            }
                        }
                        
                        // Actions
                        VStack(spacing: WovenTheme.spacing12) {
                            Button {
                                localAuth.lock()
                            } label: {
                                HStack {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 16))
                                    Text("Lock Vault")
                                        .font(WovenTheme.headline())
                                }
                                .foregroundColor(WovenTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(WovenTheme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous))
                            }
                            
                            Button {
                                authManager.signOut()
                                localAuth.lock()
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 16))
                                    Text("Sign Out")
                                        .font(WovenTheme.headline())
                                }
                                .foregroundColor(WovenTheme.error)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(WovenTheme.error.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous))
                            }
                        }
                        .padding(.top, WovenTheme.spacing8)
                    }
                    .padding(.horizontal, WovenTheme.spacing20)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(WovenTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Profile Card
    
    private var displayName: String {
        if let fullName = authManager.currentUser?.fullName, !fullName.isEmpty {
            return fullName
        }
        return authManager.currentUser?.username ?? "User"
    }
    
    private var profileCard: some View {
        HStack(spacing: WovenTheme.spacing16) {
            // Avatar with gradient border
            ZStack {
                Circle()
                    .fill(WovenTheme.primaryGradient)
                    .frame(width: 64, height: 64)
                
                Circle()
                    .fill(WovenTheme.cardBackground)
                    .frame(width: 58, height: 58)
                
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(WovenTheme.primaryGradient)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(WovenTheme.title2())
                    .foregroundColor(WovenTheme.textPrimary)
                
                if let username = authManager.currentUser?.username {
                    Text("@\(username)")
                        .font(WovenTheme.caption())
                        .foregroundColor(WovenTheme.textSecondary)
                }
            }
            
            Spacer()
        }
        .padding(WovenTheme.spacing20)
        .background(WovenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusXL, style: .continuous))
    }
    
    // MARK: - Settings Section
    @ViewBuilder
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: WovenTheme.spacing12) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(WovenTheme.textTertiary)
                .padding(.leading, WovenTheme.spacing4)
            
            VStack(spacing: 0) {
                content()
            }
            .padding(WovenTheme.spacing16)
            .background(WovenTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusLarge, style: .continuous))
        }
    }
}

// MARK: - Settings Row
struct SettingsRow<Accessory: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let iconColor: Color
    let accessory: () -> Accessory
    
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        iconColor: Color,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.iconColor = iconColor
        self.accessory = accessory
    }
    
    var body: some View {
        HStack(spacing: WovenTheme.spacing12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(WovenTheme.body())
                    .foregroundColor(WovenTheme.textPrimary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(WovenTheme.caption())
                        .foregroundColor(WovenTheme.textSecondary)
                }
            }
            
            Spacer()
            
            accessory()
        }
        .padding(.vertical, WovenTheme.spacing4)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthenticationManager())
        .environmentObject(LocalAuthenticationManager())
}
