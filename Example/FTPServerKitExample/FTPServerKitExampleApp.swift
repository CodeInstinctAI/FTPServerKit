//
//  FTPServerKitExampleApp.swift
//  FTPServerKitExample
//
//  Created by Marc Janga on 13/10/2025.
//

import SwiftUI

@main
struct FTPServerKitExampleApp: App {
    // One shared instance for both tabs
    @StateObject private var serverManager = ServerManager()
    @StateObject private var networkMonitor = NetworkMonitor()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverManager)
                .environmentObject(networkMonitor)
        }
        .onChange(of: scenePhase) { _, phase in
            // The server only runs while the app is active
            if phase == .background {
                serverManager.stopServer()
            }
        }
    }
}
