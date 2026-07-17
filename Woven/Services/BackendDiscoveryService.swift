import Foundation
import Combine

/// Service that discovers the backend API on the local network
@MainActor
class BackendDiscoveryService: ObservableObject {
    static let shared = BackendDiscoveryService()
    
    @Published var discoveredURL: String?
    @Published var isDiscovering = false
    
    private let configuredURL = AppConfiguration.configuredBaseURLString
    
    private init() {
        discoverBackend()
    }
    
    /// Explicitly trigger local network permission prompt by making a test request
    /// Call this early in app lifecycle (e.g., during splash screen) to show permission prompt
    func requestLocalNetworkPermission() {
        Task {
            let baseURL = configuredURL
            print("🔐 Requesting local network permission via test request to: \(baseURL)")
            
            // Make a quick request to trigger the permission prompt
            // This will fail if permission isn't granted, but that's okay - it triggers the prompt
            _ = await testConnection(to: baseURL)
            
            // Wait a moment for iOS to process the permission if it was just granted
            // iOS sometimes needs a brief moment to apply the permission
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Try again after the delay to see if permission is now active
            if await testConnection(to: baseURL) {
                await MainActor.run {
                    self.discoveredURL = baseURL
                }
                print("✅ Local network permission active, backend discovered")
            }
        }
    }
    
    /// Discover backend via mDNS/Bonjour
    func discoverBackend() {
        isDiscovering = true
        
        // Try mDNS discovery first
        discoverViaMDNS()
        
        tryConfiguredURL()
    }
    
    private func discoverViaMDNS() {
        // Note: For mDNS, we'd use NetServiceBrowser
        // However, since we need to test the connection anyway,
        // we'll use the IP fallback approach which is simpler
        // and works reliably for local development
    }
    
    /// Try the explicitly configured local URL; never scan or guess addresses.
    private func tryConfiguredURL() {
        Task {
            let baseURL = configuredURL
            print("🔍 Trying configured backend URL: \(baseURL)")
            
            if await testConnection(to: baseURL) {
                await MainActor.run {
                    self.discoveredURL = baseURL
                    self.isDiscovering = false
                }
                print("✅ Discovered backend at: \(baseURL)")
            } else {
                await MainActor.run {
                    self.isDiscovering = false
                }
                print("⚠️ Could not connect to backend at \(baseURL). Make sure backend is running and IP is correct.")
            }
        }
    }
    
    /// Test if backend is available at the given URL
    private func testConnection(to baseURL: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0 // Reduced timeout for faster discovery (1 second instead of 2)
        request.cachePolicy = .reloadIgnoringLocalCacheData // Don't use cached responses
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            // Connection failed (timeout, connection refused, etc.) - this is expected for most IPs
            return false
        }
        
        return false
    }
}
