import SwiftUI

// MARK: - Woven Design System
// Inspired by Apple Wallet's premium dark aesthetic

struct WovenTheme {
    // MARK: - Core Colors
    
    /// Deep black background with subtle warmth
    static let background = Color(hex: "000000")
    
    /// Elevated surface for cards
    static let cardBackground = Color(hex: "1C1C1E")
    
    /// Slightly elevated surface
    static let surfaceElevated = Color(hex: "2C2C2E")
    
    /// Subtle separator
    static let separator = Color(hex: "38383A")
    
    // MARK: - Text Colors
    
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "8E8E93")
    static let textTertiary = Color(hex: "636366")
    
    // MARK: - Accent Colors
    
    /// Warm gold accent - primary brand color
    static let accent = Color(hex: "FFD700")
    static let accentSoft = Color(hex: "FFD700").opacity(0.15)
    
    /// Success green
    static let success = Color(hex: "30D158")
    
    /// Warning amber
    static let warning = Color(hex: "FF9F0A")
    
    /// Error red
    static let error = Color(hex: "FF453A")
    
    /// Info blue
    static let info = Color(hex: "0A84FF")
    
    // MARK: - Card Gradients (Apple Wallet style)
    
    static let soloVaultGradient = LinearGradient(
        colors: [
            Color(hex: "1A1A2E"),
            Color(hex: "16213E")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let sharedVaultGradient = LinearGradient(
        colors: [
            Color(hex: "2D1B4E"),
            Color(hex: "1A1033")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let primaryGradient = LinearGradient(
        colors: [
            Color(hex: "FFD700"),
            Color(hex: "FFA500")
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    static let subtleGradient = LinearGradient(
        colors: [
            Color(hex: "1C1C1E"),
            Color(hex: "2C2C2E")
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // MARK: - Typography
    
    static func largeTitle() -> Font {
        .system(size: 34, weight: .bold, design: .rounded)
    }
    
    static func title() -> Font {
        .system(size: 28, weight: .bold, design: .rounded)
    }
    
    static func title2() -> Font {
        .system(size: 22, weight: .bold, design: .rounded)
    }
    
    static func headline() -> Font {
        .system(size: 17, weight: .semibold, design: .rounded)
    }
    
    static func body() -> Font {
        .system(size: 17, weight: .regular, design: .rounded)
    }
    
    static func callout() -> Font {
        .system(size: 16, weight: .regular, design: .rounded)
    }
    
    static func subheadline() -> Font {
        .system(size: 15, weight: .regular, design: .rounded)
    }
    
    static func footnote() -> Font {
        .system(size: 13, weight: .regular, design: .rounded)
    }
    
    static func caption() -> Font {
        .system(size: 12, weight: .medium, design: .rounded)
    }
    
    // MARK: - Spacing
    
    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32
    
    // MARK: - Corner Radius
    
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 16
    static let cornerRadiusXL: CGFloat = 20
    static let cornerRadiusCard: CGFloat = 24
}

// MARK: - Color Extension for Hex Support

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

struct WovenCardStyle: ViewModifier {
    var gradient: LinearGradient = WovenTheme.subtleGradient
    
    func body(content: Content) -> some View {
        content
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusCard, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

struct WovenButtonStyle: ButtonStyle {
    var isEnabled: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WovenTheme.headline())
            .foregroundColor(isEnabled ? .black : WovenTheme.textSecondary)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                isEnabled
                    ? WovenTheme.primaryGradient
                    : LinearGradient(colors: [WovenTheme.separator], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusMedium, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    func wovenCard(gradient: LinearGradient = WovenTheme.subtleGradient) -> some View {
        modifier(WovenCardStyle(gradient: gradient))
    }
}

// MARK: - Animated Background

struct AnimatedMeshBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            WovenTheme.background
            
            // Subtle animated orbs
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "FFD700").opacity(0.08), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: animate ? 50 : -50, y: animate ? -100 : -150)
                .blur(radius: 60)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "0A84FF").opacity(0.05), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: animate ? -80 : -30, y: animate ? 200 : 250)
                .blur(radius: 50)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

#Preview {
    ZStack {
        AnimatedMeshBackground()
        
        VStack(spacing: 20) {
            Text("Woven")
                .font(WovenTheme.largeTitle())
                .foregroundColor(WovenTheme.textPrimary)
            
            Text("Premium Dark Theme")
                .font(WovenTheme.subheadline())
                .foregroundColor(WovenTheme.textSecondary)
            
            Button("Get Started") {}
                .buttonStyle(WovenButtonStyle())
                .padding(.horizontal, 40)
        }
    }
}


