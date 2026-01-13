//
//  ContentView.swift
//  Woven
//
//  Created by Zavier Rodrigues on 12/16/25.
//

import SwiftUI

// This file is now just for the main app structure
// AuthView.swift handles the sign in / sign up UI

#Preview("Auth") {
    AuthView()
        .environmentObject(AuthenticationManager())
}
