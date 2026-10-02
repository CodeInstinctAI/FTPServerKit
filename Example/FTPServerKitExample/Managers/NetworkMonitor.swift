//
//  NetworkMonitor.swift
//  FTPServerKitExample
//
//  Created by Marc Janga on 13/10/2025.
//

import Foundation
import Network
import Combine
import FTPServerKit

/// Monitors network connectivity and provides real-time updates on network status
final class NetworkMonitor: ObservableObject {
    @Published private(set) var networkInfo: NetworkInfo = .offline

    private let monitor = NWPathMonitor()
    private var refreshTask: Task<Void, Never>?

    init() {
        startMonitoring()
    }

    deinit {
        monitor.cancel()
        refreshTask?.cancel()
    }

    /// Start monitoring network changes
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.updateNetworkInfo(path: path)
            }
        }
        monitor.start(queue: DispatchQueue(label: "FTPServerKitExample.NetworkMonitor"))

        // Also update periodically to catch IP changes
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.updateNetworkInfo(path: self.monitor.currentPath)
            }
        }
    }

    /// Update network information based on current path
    private func updateNetworkInfo(path: NWPath) {
        let isConnected = path.status == .satisfied

        guard isConnected else {
            networkInfo = .offline
            return
        }

        // Get IP address
        let ipAddress = IPAddressHelper.getLocalIPAddress()

        // Determine connection type
        let connectionType = determineConnectionType(path: path, ipAddress: ipAddress)

        networkInfo = NetworkInfo(
            ipAddress: ipAddress,
            connectionType: connectionType,
            isConnected: isConnected
        )
    }

    /// Determine the type of network connection
    private func determineConnectionType(path: NWPath, ipAddress: String?) -> NetworkInfo.ConnectionType {
        // Check if Personal Hotspot is active
        if IPAddressHelper.isPersonalHotspotActive() {
            return .hotspot
        }

        // Check IP address range for hotspot
        if let ip = ipAddress, ip.hasPrefix("172.20.10.") {
            return .hotspot
        }

        // Check interface type
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wired
        }

        // Default to Wi-Fi if we have an IP but can't determine type
        if ipAddress != nil {
            return .wifi
        }

        return .offline
    }
}
