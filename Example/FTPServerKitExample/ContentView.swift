//
//  ContentView.swift
//  FTPServerKitExample
//
//  Created by Marc Janga on 13/10/2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ShareFilesView()
                .tabItem {
                    Label("Share Files", systemImage: "folder.fill")
                }

            ConnectionView()
                .tabItem {
                    Label("Connection", systemImage: "network")
                }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ServerManager())
        .environmentObject(NetworkMonitor())
}
