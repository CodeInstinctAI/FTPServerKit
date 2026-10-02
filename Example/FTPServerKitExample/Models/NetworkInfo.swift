//
//  NetworkInfo.swift
//  FTPServerKitExample
//
//  Created by Marc Janga on 13/10/2025.
//

import Foundation

/// Represents the current network connection information
struct NetworkInfo: Equatable {
    let ipAddress: String?
    let connectionType: ConnectionType
    let isConnected: Bool
    
    enum ConnectionType: String {
        case wifi = "Wi-Fi"
        case hotspot = "Personal Hotspot"
        case cellular = "Cellular"
        case wired = "Wired"
        case offline = "Offline"
        
        var iconName: String {
            switch self {
            case .wifi:
                return "wifi"
            case .hotspot:
                return "personalhotspot"
            case .cellular:
                return "antenna.radiowaves.left.and.right"
            case .wired:
                return "cable.connector"
            case .offline:
                return "wifi.slash"
            }
        }
        
        var color: String {
            switch self {
            case .wifi, .hotspot:
                return "green"
            case .cellular, .wired:
                return "blue"
            case .offline:
                return "red"
            }
        }
    }
    
    static let offline = NetworkInfo(
        ipAddress: nil,
        connectionType: .offline,
        isConnected: false
    )
}

