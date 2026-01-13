import SwiftUI
import LocalAuthentication

struct EnableFaceIDView: View {
    @Binding var hasEnabledFaceID: Bool
    @ObservedObject var localAuth: LocalAuthenticationManager
    @State private var isEnabling = false
    @State private var appeared = false
    @State private var iconScale: CGFloat = 0.8
    
    var body: some View {
        ZStack {
            // Dark background
            WovenTheme.background
                .ignoresSafeArea()
            
            // Ambient glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [WovenTheme.accent.opacity(0.1), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(y: -100)
                .blur(radius: 50)
            
            VStack(spacing: 0) {
                Spacer()
                
                // Content
                VStack(spacing: WovenTheme.spacing32) {
                    // Icon with glow
                    ZStack {
                        Circle()
                            .fill(WovenTheme.accent.opacity(0.1))
                            .frame(width: 160, height: 160)
                            .blur(radius: 30)
                        
                        ZStack {
                            Circle()
                                .fill(WovenTheme.cardBackground)
                                .frame(width: 120, height: 120)
                            
                            Image(systemName: biometryIcon)
                                .font(.system(size: 50))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [WovenTheme.accent, WovenTheme.accent.opacity(0.7)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                        .scaleEffect(iconScale)
                    }
                    .opacity(appeared ? 1 : 0)
                    
                    // Text
                    VStack(spacing: WovenTheme.spacing12) {
                        Text("Enable \(localAuth.biometryName)")
                            .font(WovenTheme.title())
                            .foregroundColor(WovenTheme.textPrimary)
                            .multilineTextAlignment(.center)
                        
                        Text("Quickly and securely unlock your vault with \(localAuth.biometryName).")
                            .font(WovenTheme.body())
                            .foregroundColor(WovenTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, WovenTheme.spacing20)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                }
                
                Spacer()
                
                // Buttons
                VStack(spacing: WovenTheme.spacing16) {
                    Button {
                        Task {
                            isEnabling = true
                            await localAuth.authenticate()
                            isEnabling = false
                            if localAuth.isUnlocked {
                                hasEnabledFaceID = true
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if isEnabling {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Image(systemName: biometryIcon)
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            Text("Enable \(localAuth.biometryName)")
                        }
                    }
                    .buttonStyle(WovenButtonStyle())
                    .disabled(isEnabling)
                    
                    // Skip option
                    Button {
                        hasEnabledFaceID = true
                    } label: {
                        Text("Set up later")
                            .font(WovenTheme.subheadline())
                            .foregroundColor(WovenTheme.textSecondary)
                    }
                    .padding(.top, WovenTheme.spacing4)
                }
                .padding(.horizontal, WovenTheme.spacing24)
                .padding(.bottom, 50)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                appeared = true
                iconScale = 1.0
            }
        }
    }
    
    private var biometryIcon: String {
        switch localAuth.biometryType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .none:
            return "lock.fill"
        @unknown default:
            return "lock.fill"
        }
    }
}

#Preview {
    EnableFaceIDView(
        hasEnabledFaceID: .constant(false),
        localAuth: LocalAuthenticationManager()
    )
}
