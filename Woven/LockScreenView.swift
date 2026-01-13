import SwiftUI
import LocalAuthentication

struct LockScreenView: View {
    @ObservedObject var localAuth: LocalAuthenticationManager
    @State private var isAuthenticating = false
    @State private var appeared = false
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // Dark background
            WovenTheme.background
                .ignoresSafeArea()
            
            // Ambient glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [WovenTheme.accent.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                )
                .frame(width: 500, height: 500)
                .blur(radius: 60)
                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
            
            VStack(spacing: 40) {
                Spacer()
                
                // Logo and icon
                VStack(spacing: WovenTheme.spacing24) {
                    ZStack {
                        // Outer glow
                        Circle()
                            .fill(WovenTheme.accent.opacity(0.1))
                            .frame(width: 160, height: 160)
                            .blur(radius: 30)
                        
                        // Icon container
                        ZStack {
                            Circle()
                                .fill(WovenTheme.cardBackground)
                                .frame(width: 120, height: 120)
                            
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [WovenTheme.accent.opacity(0.5), WovenTheme.accent.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 120, height: 120)
                            
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [WovenTheme.accent, WovenTheme.accent.opacity(0.7)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                    }
                    .scaleEffect(appeared ? 1 : 0.8)
                    .opacity(appeared ? 1 : 0)
                    
                    VStack(spacing: WovenTheme.spacing8) {
                        Text("Woven")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(WovenTheme.textPrimary)
                        
                        Text("Your private vault")
                            .font(WovenTheme.subheadline())
                            .foregroundColor(WovenTheme.textSecondary)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                }
                
                Spacer()
                
                // Unlock button
                VStack(spacing: WovenTheme.spacing16) {
                    Button {
                        Task {
                            isAuthenticating = true
                            await localAuth.authenticate()
                            isAuthenticating = false
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if isAuthenticating {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Image(systemName: biometryIcon)
                                    .font(.system(size: 20, weight: .semibold))
                            }
                            
                            Text(isAuthenticating ? "Authenticating..." : "Unlock with \(localAuth.biometryName)")
                        }
                    }
                    .buttonStyle(WovenButtonStyle())
                    .disabled(isAuthenticating)
                    .padding(.horizontal, WovenTheme.spacing24)
                    
                    if let error = localAuth.authError {
                        Text(error)
                            .font(WovenTheme.caption())
                            .foregroundColor(WovenTheme.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, WovenTheme.spacing32)
                    }
                }
                .padding(.bottom, 60)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                appeared = true
            }
            
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
            
            // Auto-trigger authentication
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if !localAuth.isUnlocked {
                    isAuthenticating = true
                    await localAuth.authenticate()
                    isAuthenticating = false
                }
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
    LockScreenView(localAuth: LocalAuthenticationManager())
}
