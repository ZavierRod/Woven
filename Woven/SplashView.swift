import SwiftUI

struct SplashView: View {
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    @State private var ringRotation: Double = 0
    @State private var glowOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // Dark background
            WovenTheme.background
                .ignoresSafeArea()
            
            // Subtle animated glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [WovenTheme.accent.opacity(0.15), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .blur(radius: 60)
                .opacity(glowOpacity)
            
            // Subtle woven pattern background
            GeometryReader { geometry in
                Canvas { context, size in
                    let spacing: CGFloat = 40
                    let lineWidth: CGFloat = 0.5
                    
                    for i in stride(from: -size.height, to: size.width + size.height, by: spacing) {
                        var path = Path()
                        path.move(to: CGPoint(x: i, y: 0))
                        path.addLine(to: CGPoint(x: i - size.height, y: size.height))
                        context.stroke(path, with: .color(.white.opacity(0.03)), lineWidth: lineWidth)
                    }
                    
                    for i in stride(from: 0, to: size.width + size.height, by: spacing) {
                        var path = Path()
                        path.move(to: CGPoint(x: i, y: 0))
                        path.addLine(to: CGPoint(x: i + size.height, y: size.height))
                        context.stroke(path, with: .color(.white.opacity(0.03)), lineWidth: lineWidth)
                    }
                }
            }
            .ignoresSafeArea()
            
            // Centered content
            VStack(spacing: 20) {
                // Woven loop glyph with animation
                ZStack {
                    // Outer glow ring
                    Circle()
                        .stroke(WovenTheme.accent.opacity(0.2), lineWidth: 2)
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(ringRotation))
                    
                    // Interlocking rings (woven symbol)
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [WovenTheme.accent.opacity(0.8), WovenTheme.accent.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 50, height: 50)
                        .offset(x: -14)
                    
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [WovenTheme.accent.opacity(0.4), WovenTheme.accent.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 50, height: 50)
                        .offset(x: 14)
                }
                
                // Wordmark
                Text("Woven")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Entrance animation
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            
            withAnimation(.easeInOut(duration: 1.5).delay(0.3)) {
                glowOpacity = 1.0
            }
            
            // Continuous subtle rotation
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }
}

#Preview {
    SplashView()
}
