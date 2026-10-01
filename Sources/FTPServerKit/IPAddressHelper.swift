//
//  IPAddressHelper.swift
//  FTPServerKit
//
//  Created by Marc Janga on 11/11/2025.
//

import Foundation

/// Finds the device's IP addresses and network interfaces.
public enum IPAddressHelper {

    /// Get the current local IP address using getifaddrs()
    public static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee, interface.ifa_addr != nil else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family

            // We're looking for IPv4 addresses
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)

                // Check for Wi-Fi (en0) or hotspot (bridge100) interfaces
                if name == "en0" || name.hasPrefix("bridge") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        socklen_t(0),
                        NI_NUMERICHOST
                    )
                    address = string(fromNullTerminated: hostname)

                    // Prefer bridge interface (hotspot) over en0 (Wi-Fi)
                    if name.hasPrefix("bridge") {
                        return address
                    }
                }
            }
        }

        return address
    }

    /// Detect if the device is in Personal Hotspot mode
    public static func isPersonalHotspotActive() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return false }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee, interface.ifa_addr != nil else { continue }
            let name = String(cString: interface.ifa_name)

            // Personal Hotspot typically uses bridge100 interface
            if name.hasPrefix("bridge") {
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        socklen_t(0),
                        NI_NUMERICHOST
                    )
                    let address = string(fromNullTerminated: hostname)

                    // Personal Hotspot typically uses 172.20.10.x range
                    if address.hasPrefix("172.20.10.") {
                        return true
                    }
                }
            }
        }

        return false
    }

    /// Get the interface name for the current connection
    public static func getCurrentInterfaceName() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee, interface.ifa_addr != nil else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)

                if name == "en0" || name.hasPrefix("bridge") {
                    return name
                }
            }
        }

        return nil
    }

    private static func string(fromNullTerminated buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
