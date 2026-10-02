//
//  ConnectionView.swift
//  FTPServerKitExample
//
//  Created by Marc Janga on 13/10/2025.
//

import SwiftUI

/// View displaying network connection information and Personal Hotspot instructions
struct ConnectionView: View {
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var serverManager: ServerManager
    @State private var showingHotspotInstructions = false
    @State private var copiedURLs: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Network Status Card
                    networkStatusCard

                    // Active Servers Section
                    if !serverManager.activeServers.isEmpty {
                        activeServersSection
                    }

                    // Commands and responses from the server delegate
                    if !serverManager.recentActivity.isEmpty {
                        activityCard
                    }

                    // IP Address Card (General Info)
                    if networkMonitor.networkInfo.isConnected {
                        generalNetworkInfoCard
                    }

                    // Personal Hotspot Section
                    personalHotspotSection

                    // Privacy Notice
                    privacyNoticeCard
                }
                .padding()
            }
            .navigationTitle("Connection")
            .background(Color(.systemGroupedBackground))
        }
    }
    
    // MARK: - Network Status Card
    
    private var networkStatusCard: some View {
        VStack(spacing: 16) {
            Image(systemName: networkMonitor.networkInfo.connectionType.iconName)
                .font(.system(size: 50))
                .foregroundStyle(colorForConnectionType)
            
            Text(networkMonitor.networkInfo.connectionType.rawValue)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(networkMonitor.networkInfo.isConnected ? "Connected" : "Not Connected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Active Servers Section

    private var activeServersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Active Servers", systemImage: "server.rack")
                .font(.headline)

            Divider()

            ForEach(serverManager.activeServers) { activeServer in
                serverCard(for: activeServer.connectionInfo)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    // MARK: - Server Card

    private func serverCard(for info: ServerConnectionInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Server Type Header
            HStack {
                Image(systemName: info.serverType.iconName)
                    .foregroundStyle(.blue)
                Text("\(info.serverType.rawValue) Server")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("Port \(String(info.port))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Server URL
            VStack(alignment: .leading, spacing: 4) {
                Text("Address")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(info.url)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.blue)
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = info.url
                        copiedURLs.insert(info.url)

                        // Reset after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedURLs.remove(info.url)
                        }
                    } label: {
                        Image(systemName: copiedURLs.contains(info.url) ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(copiedURLs.contains(info.url) ? .green : .blue)
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }

            // Credentials (for FTP)
            if let credentials = info.credentials {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Credentials")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("User: \(credentials.username)")
                                .font(.system(.caption, design: .monospaced))
                            Text("Pass: \(credentials.password)")
                                .font(.system(.caption, design: .monospaced))
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray5).opacity(0.3))
        .cornerRadius(8)
    }

    // MARK: - Activity Card

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Activity", systemImage: "list.bullet.rectangle")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(serverManager.recentActivity.prefix(15).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    // MARK: - General Network Info Card

    private var generalNetworkInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Network Information", systemImage: "network")
                .font(.headline)

            Divider()

            // IP Address
            VStack(alignment: .leading, spacing: 8) {
                Text("IP Address")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(networkMonitor.networkInfo.ipAddress ?? "Not Available")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.medium)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Personal Hotspot Section
    
    private var personalHotspotSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation {
                    showingHotspotInstructions.toggle()
                }
            } label: {
                HStack {
                    Label("Share via Personal Hotspot", systemImage: "personalhotspot")
                        .font(.headline)
                    
                    Spacer()
                    
                    Image(systemName: showingHotspotInstructions ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            
            if showingHotspotInstructions {
                Divider()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("To share files via Personal Hotspot:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        InstructionStep(number: 1, text: "Open the Settings app on this device")
                        InstructionStep(number: 2, text: "Navigate to Cellular → Personal Hotspot (or Settings → Personal Hotspot on iPad)")
                        InstructionStep(number: 3, text: "Toggle 'Allow Others to Join' to ON")
                        InstructionStep(number: 4, text: "Note your Wi-Fi password shown on the screen")
                        InstructionStep(number: 5, text: "On the other device, connect to your hotspot using the password")
                        InstructionStep(number: 6, text: hotspotAccessInstructions)
                    }
                    
                    Text("⚠️ Note: Due to iOS security restrictions, this app cannot automatically enable Personal Hotspot or retrieve the password. You must enable it manually in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    
                    Button {
                        openSettings()
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Privacy Notice Card
    
    private var privacyNoticeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Privacy & Security", systemImage: "lock.shield")
                .font(.headline)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                PrivacyPoint(icon: "network", text: "Files are only shared on your local network")
                PrivacyPoint(icon: "icloud.slash", text: "No data is uploaded to the internet")
                PrivacyPoint(icon: "app.badge", text: "Server only runs while app is active")
                PrivacyPoint(icon: "lock", text: "Other devices need the username and password to access files")
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Helper Views

    private var colorForConnectionType: Color {
        switch networkMonitor.networkInfo.connectionType {
        case .wifi, .hotspot:
            return .green
        case .cellular, .wired:
            return .blue
        case .offline:
            return .red
        }
    }

    private var hotspotAccessInstructions: String {
        if serverManager.activeServers.isEmpty {
            return "Start the FTP server first, then it will be accessible at 172.20.10.1"
        }

        let serverInstructions = serverManager.activeServers.map { server in
            "FTP: ftp://172.20.10.1:\(server.connectionInfo.port) (\(ServerManager.username)/\(ServerManager.password))"
        }.joined(separator: "\n")

        return "Server will be accessible at:\n\(serverInstructions)"
    }

    private func openSettings() {
        // Try to open Personal Hotspot settings
        if let url = URL(string: "App-prefs:root=INTERNET_TETHERING") {
            UIApplication.shared.open(url)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            // Fallback to general settings
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Supporting Views

struct InstructionStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.blue))
            
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PrivacyPoint: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    ConnectionView()
        .environmentObject(NetworkMonitor())
        .environmentObject(ServerManager())
}

