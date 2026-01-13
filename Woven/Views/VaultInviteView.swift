import SwiftUI

struct VaultInviteView: View {
    let vaultId: UUID
    @Environment(Router.self) private var router
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundColor(.purple)
            
            Text("Vault Invitation")
                .font(.title)
                .bold()
            
            Text("You've been invited to join a secure vault.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Text("Vault ID: \(vaultId)")
                .font(.caption)
                .monospaced()
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            
            HStack(spacing: 20) {
                Button(action: {
                    router.pop()
                }) {
                    Text("Decline")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(12)
                }
                
                Button(action: {
                    // Accept logic
                    router.pop()
                }) {
                    Text("Accept")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Invitation")
    }
}
