//
//  IPAddressHelper.swift
//  FTPServerKit
//
//  Created by Marc Janga on 11/11/2025.
//

import Foundation

/// Finds the device's IP addresses and network interfaces.
public enum IPAddressHelper {

    /// The device's IPv4 address on Personal Hotspot or Wi-Fi, for showing clients where to connect.
    ///
    /// Prefers the Personal Hotspot address when both are active. Returns `nil` when the device has neither.
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

    /// Whether Personal Hotspot is on and has an address in its usual `172.20.10.x` range.
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

    /// The name of the first interface with an IPv4 address on Wi-Fi (`en0`) or Personal Hotspot (`bridge…`).
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
