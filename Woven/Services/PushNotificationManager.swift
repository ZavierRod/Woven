import SwiftUI
import UserNotifications

@Observable class PushNotificationManager: NSObject {
    static let shared = PushNotificationManager()
    
    var deviceToken: String?
    var isPermissionGranted = false
    var lastNotificationPayload: [AnyHashable: Any]?
    
    override init() {
        super.init()
        checkPermissionStatus()
    }
    
    func requestPermission() {
        print("📲 [Push] Requesting permission...")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.isPermissionGranted = granted
                print("📲 [Push] Permission granted: \(granted), error: \(String(describing: error))")
                if granted {
                    print("📲 [Push] Registering for remote notifications...")
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }
    
    func checkPermissionStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isPermissionGranted = settings.authorizationStatus == .authorized
            }
        }
    }
    
    func handleDeviceToken(_ tokenData: Data) {
        let tokenParts = tokenData.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        self.deviceToken = token
        print("📲 [Push] Device Token: \(token)")
        
        // Only register if user is authenticated (has auth token)
        if KeychainHelper.shared.read(key: "woven-session-token") != nil {
            Task {
                await registerTokenWithRetry(token: token, maxRetries: 3)
            }
        } else {
            print("📲 [Push] Token stored locally, will register after login")
        }
    }
    
    /// Call this after user logs in to register any pending device token
    func registerPendingTokenIfNeeded() {
        guard let token = deviceToken else {
            print("📲 [Push] No pending token to register")
            return
        }
        
        guard KeychainHelper.shared.read(key: "woven-session-token") != nil else {
            print("📲 [Push] No auth token, skipping registration")
            return
        }
        
        print("📲 [Push] Registering pending device token after login...")
        Task {
            await registerTokenWithRetry(token: token, maxRetries: 3)
        }
    }
    
    /// Register device token with retry logic to handle local network permission delays
    private func registerTokenWithRetry(token: String, maxRetries: Int, retryCount: Int = 0) async {
        do {
            // Add a small delay on retries to allow iOS to process local network permission
            if retryCount > 0 {
                let delay = UInt64(retryCount) * 1_000_000_000 // 1 second per retry
                print("🔄 [Push] Retrying token registration (attempt \(retryCount + 1)/\(maxRetries + 1)) after \(retryCount) second delay...")
                try? await Task.sleep(nanoseconds: delay)
            }
            
            try await APIService.shared.registerDeviceToken(token: token)
            print("✅ [Push] Token registered with backend")
        } catch {
            if retryCount < maxRetries {
                print("⚠️ [Push] Token registration failed, will retry: \(error.localizedDescription)")
                await registerTokenWithRetry(token: token, maxRetries: maxRetries, retryCount: retryCount + 1)
            } else {
                print("❌ [Push] Failed to register token after \(maxRetries + 1) attempts: \(error)")
                print("💡 [Push] Tip: If local network permission was just granted, try restarting the app")
            }
        }
    }
    
    func handleNotification(userInfo: [AnyHashable: Any], router: Router) {
        print("📩 [Push] Received payload: \(userInfo)")
        self.lastNotificationPayload = userInfo
        
        guard let type = userInfo["type"] as? String else { return }
        
        DispatchQueue.main.async {
            switch type {
            case "friend_request":
                let requestId = (userInfo["request_id"] as? String).flatMap { Int($0) } ?? (userInfo["request_id"] as? Int)
                router.navigate(to: .friendRequests(requestId: requestId))
                
            case "vault_invite":
                if let vaultIdString = userInfo["vault_id"] as? String,
                   let vaultId = UUID(uuidString: vaultIdString) {
                    router.navigate(to: .vaultInvite(vaultId: vaultId))
                }
                
            case "access_request":
                // Handle access request approval notification
                if let requestIdString = userInfo["request_id"] as? String,
                   let requestId = Int(requestIdString) {
                    router.navigate(to: .accessRequest(requestId: requestId))
                } else if let requestId = userInfo["request_id"] as? Int {
                    router.navigate(to: .accessRequest(requestId: requestId))
                }
                
            default:
                break
            }
        }
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    // Handle foreground notifications
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        print("🔔 [Push] Foreground notification: \(userInfo)")
        self.lastNotificationPayload = userInfo
        return [.banner, .sound, .badge]
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        print("point of interest")
        // We need access to the router here. 
        // Since delegate methods are called by system, we'll rely on the app state or a global router reference if needed,
        // but typically we handle this by passing the info to a handler that has access to the router.
        // For now, we'll store it and let the UI react or use a notification center broadcast.
        
        // Better approach: Post a notification that WovenApp observes, or use a closure if we can inject it.
        // Given the architecture, let's use NotificationCenter to broadcast the tap event to the main app view which holds the router.
        NotificationCenter.default.post(name: NSNotification.Name("PushNotificationTapped"), object: nil, userInfo: userInfo)
    }
}
