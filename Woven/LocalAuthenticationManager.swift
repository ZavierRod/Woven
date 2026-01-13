import Foundation
import LocalAuthentication
import SwiftUI
import Combine

@MainActor
final class LocalAuthenticationManager: ObservableObject {
    @Published var isUnlocked: Bool = false
    @Published var authError: String?
    
    private let context = LAContext()
    
    var biometryType: LABiometryType {
        context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }
    
    var biometryName: String {
        switch biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Passcode"
        @unknown default:
            return "Biometrics"
        }
    }
    
    func authenticate() async {
        let context = LAContext()
        context.localizedCancelTitle = "Use Passcode"
        
        var error: NSError?
        
        // Check if biometric authentication is available
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = "Unlock your Woven vault"
            
            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: reason
                )
                
                if success {
                    self.isUnlocked = true
                    self.authError = nil
                }
            } catch let authError as LAError {
                self.isUnlocked = false
                
                switch authError.code {
                case .userCancel:
                    self.authError = "Authentication cancelled"
                case .userFallback:
                    // User chose to use passcode - this is handled by the system
                    break
                case .biometryNotAvailable:
                    self.authError = "Biometric authentication not available"
                case .biometryNotEnrolled:
                    self.authError = "No biometrics enrolled. Please set up Face ID or Touch ID."
                case .biometryLockout:
                    self.authError = "Biometrics locked. Please use your passcode."
                default:
                    self.authError = "Authentication failed"
                }
            } catch {
                self.isUnlocked = false
                self.authError = "Authentication failed"
            }
        } else {
            self.authError = "Device authentication not available"
        }
    }
    
    func lock() {
        isUnlocked = false
    }
}

