import SwiftUI

struct VaultView: View {
    @State private var showAddMedia = false
    @State private var appeared = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                WovenTheme.background.ignoresSafeArea()
                
                VStack {
                    // Empty state
                    VStack(spacing: WovenTheme.spacing24) {
                        Spacer()
                        
                        // Icon with glow
                        ZStack {
                            Circle()
                                .fill(WovenTheme.accent.opacity(0.1))
                                .frame(width: 140, height: 140)
                                .blur(radius: 30)
                            
                            ZStack {
                                Circle()
                                    .fill(WovenTheme.cardBackground)
                                    .frame(width: 120, height: 120)
                                
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 50))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [WovenTheme.accent, WovenTheme.accent.opacity(0.6)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        }
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.8)
                        
                        VStack(spacing: WovenTheme.spacing8) {
                            Text("Your vault is empty")
                                .font(WovenTheme.title2())
                                .foregroundColor(WovenTheme.textPrimary)
                            
                            Text("Add photos and videos to keep them\nsafe and encrypted")
                                .font(WovenTheme.subheadline())
                                .foregroundColor(WovenTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                        
                        Button {
                            showAddMedia = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Add Media")
                            }
                        }
                        .buttonStyle(WovenButtonStyle())
                        .padding(.horizontal, 80)
                        .padding(.top, WovenTheme.spacing8)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Vault")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(WovenTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddMedia = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(WovenTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $showAddMedia) {
                AddMediaView()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }
}

struct AddMediaView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                WovenTheme.background.ignoresSafeArea()
                
                VStack(spacing: WovenTheme.spacing24) {
                    VStack(spacing: WovenTheme.spacing16) {
                        ZStack {
                            Circle()
                                .fill(WovenTheme.accent.opacity(0.1))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 36))
                                .foregroundColor(WovenTheme.accent)
                        }
                        
                        Text("Add Media")
                            .font(WovenTheme.title2())
                            .foregroundColor(WovenTheme.textPrimary)
                        
                        Text("Choose photos or videos to encrypt and store securely")
                            .font(WovenTheme.subheadline())
                            .foregroundColor(WovenTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    
                    VStack(spacing: WovenTheme.spacing12) {
                        MediaOptionButton(
                            icon: "photo.on.rectangle",
                            title: "Photo Library",
                            subtitle: "Choose from your photos"
                        ) {
                            // Photo library action
                        }
                        
                        MediaOptionButton(
                            icon: "camera",
                            title: "Take Photo",
                            subtitle: "Use camera to capture"
                        ) {
                            // Camera action
                        }
                    }
                    .padding(.horizontal, WovenTheme.spacing20)
                    
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(WovenTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(WovenTheme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct MediaOptionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: WovenTheme.spacing16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WovenTheme.accent.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(WovenTheme.accent)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(WovenTheme.headline())
                        .foregroundColor(WovenTheme.textPrimary)
                    
                    Text(subtitle)
                        .font(WovenTheme.caption())
                        .foregroundColor(WovenTheme.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(WovenTheme.textTertiary)
            }
            .padding(WovenTheme.spacing16)
            .background(WovenTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: WovenTheme.cornerRadiusLarge, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VaultView()
}
