import SwiftUI

struct FriendRequestsView: View {
    let requestId: Int?
    @Environment(Router.self) private var router
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Friend Requests")
                .font(.title)
                .bold()
            
            if let id = requestId {
                Text("Highlighting Request ID: \(id)")
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            
            List {
                // Placeholder list
                ForEach(1...3, id: \.self) { i in
                    HStack {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 40)
                        
                        VStack(alignment: .leading) {
                            Text("User \(i)")
                                .font(.headline)
                            Text("Sent you a request")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Accept") {
                            // Action
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Requests")
    }
}
