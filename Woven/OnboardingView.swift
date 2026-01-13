import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var appeared = false
    
    var body: some View {
        ZStack {
            // Dark background with subtle gradient
            WovenTheme.background
                .ignoresSafeArea()
            
            // Animated background orbs
            GeometryReader { geo in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [WovenTheme.accent.opacity(0.08), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .position(x: geo.size.width * 0.8, y: geo.size.height * 0.2)
                    .blur(radius: 40)
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "A855F7").opacity(0.05), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                    .frame(width: 300, height: 300)
                    .position(x: geo.size.width * 0.2, y: geo.size.height * 0.7)
                    .blur(radius: 40)
            }
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    OnboardingPage(
                        icon: "lock.shield.fill",
                        iconColor: WovenTheme.accent,
                        headline: "A private vault for what matters.",
                        subtext: "End-to-end encrypted. Solo or shared with one person."
                    )
                    .tag(0)
                    
                    OnboardingPage(
                        icon: "person.2.fill",
                        iconColor: Color(hex: "A855F7"),
                        headline: "Shared vaults require consent.",
                        subtext: "Access can require approval from your partner."
                    )
                    .tag(1)
                    
                    OnboardingPage(
                        icon: "eye.trianglebadge.exclamationmark",
                        iconColor: WovenTheme.warning,
                        headline: "Your vault can't stop copying.",
                        subtext: "We detect screenshots and recording when possible and alert your partner, but nothing can prevent a second camera."
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Bottom section
                VStack(spacing: WovenTheme.spacing24) {
                    // Page indicators
                    HStack(spacing: 8) {
                        ForEach(0..<3) { index in
                            Capsule()
                                .fill(currentPage == index ? WovenTheme.accent : WovenTheme.textTertiary)
                                .frame(width: currentPage == index ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentPage)
                        }
                    }
                    
                    // CTA Button
                    Button {
                        if currentPage < 2 {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                currentPage += 1
                            }
                        } else {
                            hasCompletedOnboarding = true
                        }
                    } label: {
                        Text(currentPage < 2 ? "Continue" : "Get Started")
                    }
                    .buttonStyle(WovenButtonStyle())
                    .padding(.horizontal, WovenTheme.spacing24)
                }
                .padding(.bottom, 50)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }
}

struct OnboardingPage: View {
    let icon: String
    let iconColor: Color
    let headline: String
    let subtext: String
    
    @State private var iconScale: CGFloat = 0.8
    @State private var iconOpacity: Double = 0
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Icon with glow
            ZStack {
                // Glow effect
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 160, height: 160)
                    .blur(radius: 30)
                
                // Icon container
                ZStack {
                    Circle()
                        .fill(WovenTheme.cardBackground)
                        .frame(width: 140, height: 140)
                    
                    Circle()
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 140, height: 140)
                    
                    Image(systemName: icon)
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [iconColor, iconColor.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
            }
            .padding(.bottom, 48)
            
            // Text content
            VStack(spacing: WovenTheme.spacing16) {
                Text(headline)
                    .font(WovenTheme.title())
                    .foregroundColor(WovenTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(subtext)
                    .font(WovenTheme.body())
                    .foregroundColor(WovenTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 32)
            
            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
        }
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
}
