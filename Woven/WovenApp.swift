//
//  WovenApp.swift
//  Woven
//
//  Created by Zavier Rodrigues on 12/16/25.
//

import SwiftUI

@main
struct WovenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var localAuth = LocalAuthenticationManager()
    @State private var router = Router()
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var showPrivacyOverlay = false
    @State private var showSplash = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasSetupFaceID") private var hasSetupFaceID = false
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main app flow
                if showSplash {
                    SplashView()
                    .transition(.opacity)
                } else if !hasCompletedOnboarding {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.opacity)
                } else if !authManager.isAuthenticated {
                    AuthView()
                    .environmentObject(authManager)
                    .transition(.opacity)
                } else if !hasSetupFaceID {
                    EnableFaceIDView(hasEnabledFaceID: $hasSetupFaceID, localAuth: localAuth)
                    .transition(.opacity)
                } else if !localAuth.isUnlocked {
                    LockScreenView(localAuth: localAuth)
                    .transition(.opacity)
                } else {
                    NavigationStack(path: $router.path) {
                        MainTabView()
                            .environmentObject(authManager)
                            .environmentObject(localAuth)
                            .environment(router)
                            .navigationDestination(for: Route.self) { route in
                                switch route {
                                case .friendRequests(let requestId):
                                    FriendRequestsView(requestId: requestId)
                                case .vaultInvite(let vaultId):
                                    VaultInviteView(vaultId: vaultId)
                                case .home:
                                    EmptyView()
                                }
                            }
                    }
                    .transition(.opacity)
                }
                
                // Privacy overlay for app switcher
                if showPrivacyOverlay && !showSplash {
                    PrivacyOverlayView()
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSplash)
            .animation(.easeInOut(duration: 0.3), value: hasCompletedOnboarding)
            .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
            .animation(.easeInOut(duration: 0.3), value: hasSetupFaceID)
            .animation(.easeInOut(duration: 0.3), value: localAuth.isUnlocked)
            .animation(.easeInOut(duration: 0.2), value: showPrivacyOverlay)
            .onAppear {
                // #region agent log
                print("🔍 [DEBUG-B] App onAppear - hasCompletedOnboarding: \(hasCompletedOnboarding), isAuthenticated: \(authManager.isAuthenticated), hasSetupFaceID: \(hasSetupFaceID), isUnlocked: \(localAuth.isUnlocked)")
                // #endregion
                
                // Request local network permission immediately on app launch
                // This triggers the iOS permission prompt early, before any critical operations
                BackendDiscoveryService.shared.requestLocalNetworkPermission()
                
                // Show splash for 1.5 seconds then transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        showSplash = false
                    }
                    // #region agent log
                    print("🔍 [DEBUG-B] After splash - hasCompletedOnboarding: \(hasCompletedOnboarding), isAuthenticated: \(authManager.isAuthenticated), hasSetupFaceID: \(hasSetupFaceID), isUnlocked: \(localAuth.isUnlocked)")
                    // #endregion
                    
                    // Request push permissions after splash
                    PushNotificationManager.shared.requestPermission()
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(from: oldPhase, to: newPhase)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PushNotificationTapped"))) { notification in
                if let userInfo = notification.userInfo as? [AnyHashable: Any] {
                    // Handle deep link only if authenticated and unlocked
                    if authManager.isAuthenticated && localAuth.isUnlocked {
                        PushNotificationManager.shared.handleNotification(userInfo: userInfo, router: router)
                    } else {
                        // Store for later? For now just ignore or maybe store in PushManager to handle after unlock
                        print("⚠️ [Push] App locked or not auth, ignoring deep link for now")
                    }
                }
            }
        }
    }
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // App is active, hide privacy overlay
            showPrivacyOverlay = false
            
        case .inactive:
            // App is inactive (app switcher, notification center, etc.)
            // Show privacy overlay to hide content
            showPrivacyOverlay = true
            
        case .background:
            // App went to background
            showPrivacyOverlay = true
            // Lock the app when going to background
            localAuth.lock()
            
        @unknown default:
            break
        }
    }
}
