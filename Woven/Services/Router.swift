import SwiftUI
import Combine

enum Route: Hashable {
    case friendRequests(requestId: Int?)
    case vaultInvite(vaultId: UUID)
    case home
}

@Observable class Router {
    var path = NavigationPath()
    
    func navigate(to route: Route) {
        path.append(route)
    }
    
    func popToRoot() {
        path = NavigationPath()
    }
    
    func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
    }
}
