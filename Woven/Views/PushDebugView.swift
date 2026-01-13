import SwiftUI

struct PushDebugView: View {
    @State private var deviceToken: String = "Loading..."
    @State private var lastPayload: String = "None"
    @State private var showCopiedAlert = false
    
    var body: some View {
        List {
            Section(header: Text("Device Token")) {
                Text(deviceToken)
                    .font(.system(.caption, design: .monospaced))
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = deviceToken
                            showCopiedAlert = true
                        } label: {
                            Label("Copy Token", systemImage: "doc.on.doc")
                        }
                    }
                
                Button("Copy Token") {
                    UIPasteboard.general.string = deviceToken
                    showCopiedAlert = true
                }
            }
            
            Section(header: Text("Last Notification Payload")) {
                Text(lastPayload)
                    .font(.system(.caption, design: .monospaced))
            }
            
            Section(header: Text("Test Actions")) {
                Button("Request Permission Again") {
                    PushNotificationManager.shared.requestPermission()
                }
                
                Button("Simulate Friend Request Push") {
                    let userInfo: [AnyHashable: Any] = [
                        "type": "friend_request",
                        "request_id": 123,
                        "aps": [
                            "alert": [
                                "title": "Test Friend Request",
                                "body": "John Doe sent you a friend request"
                            ]
                        ]
                    ]
                    NotificationCenter.default.post(name: NSNotification.Name("PushNotificationTapped"), object: nil, userInfo: userInfo)
                }
                
                Button("Simulate Vault Invite Push") {
                    let userInfo: [AnyHashable: Any] = [
                        "type": "vault_invite",
                        "vault_id": UUID().uuidString,
                        "aps": [
                            "alert": [
                                "title": "Test Vault Invite",
                                "body": "Jane invited you to a vault"
                            ]
                        ]
                    ]
                    NotificationCenter.default.post(name: NSNotification.Name("PushNotificationTapped"), object: nil, userInfo: userInfo)
                }
            }
        }
        .navigationTitle("Push Debug")
        .onAppear {
            updateInfo()
        }
        .alert("Copied!", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        }
    }
    
    private func updateInfo() {
        if let token = PushNotificationManager.shared.deviceToken {
            deviceToken = token
        } else {
            deviceToken = "No token yet (check simulator vs device)"
        }
        
        if let payload = PushNotificationManager.shared.lastNotificationPayload {
            lastPayload = "\(payload)"
        }
    }
}
