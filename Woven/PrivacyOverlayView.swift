import SwiftUI

struct PrivacyOverlayView: View {
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // Dark solid background
            WovenTheme.background
                .ignoresSafeArea()
            
            // Subtle pulsing glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [WovenTheme.accent.opacity(0.08), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                .blur(radius: 40)
            
            VStack(spacing: WovenTheme.spacing20) {
                ZStack {
                    Circle()
                        .fill(WovenTheme.cardBackground)
                        .frame(width: 100, height: 100)
                    
                    Circle()
                        .stroke(WovenTheme.accent.opacity(0.3), lineWidth: 2)
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [WovenTheme.accent, WovenTheme.accent.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                
                Text("Woven")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(WovenTheme.textPrimary)
                
                Text("Protected")
                    .font(WovenTheme.subheadline())
                    .foregroundColor(WovenTheme.textSecondary)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }
}

#Preview {
    PrivacyOverlayView()
}
