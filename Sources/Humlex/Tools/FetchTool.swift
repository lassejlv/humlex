//
//  FetchTool.swift
//  AI Chat
//
//  Created by Humlex on 2/11/26.
//

import Foundation
import Darwin

/// HTTP fetch tool for making web requests.
/// Allows AI to retrieve data from APIs, websites, and other HTTP endpoints.
struct FetchTool: BuiltInTool {
    var name: String { "fetch" }
    
    var description: String {
        """
        Make HTTP requests to fetch data from URLs. Supports GET, POST, PUT, DELETE, PATCH methods.
        Returns response status, headers, and body. Useful for calling APIs, downloading data,
        or checking web resources. Has built-in safety limits (30s timeout, 50KB response limit).
        """
    }
    
    var inputSchema: [String: AnyCodable] {
        Self.objectSchema(properties: [
            "url": Self.stringProperty(description: "The URL to fetch (required). Must be a valid HTTP/HTTPS URL."),
            "method": Self.stringProperty(
                description: "HTTP method: GET, POST, PUT, DELETE, PATCH (default: GET)",
                enumValues: ["GET", "POST", "PUT", "DELETE", "PATCH"]
            ),
            "headers": Self.objectProperty(description: "Optional HTTP headers as key-value pairs (e.g., {\"Authorization\": \"Bearer token\"})"),
            "body": Self.stringProperty(description: "Optional request body for POST/PUT/PATCH (e.g., JSON payload)"),
            "timeout": Self.numberProperty(description: "Request timeout in seconds (default: 30, max: 60)", minimum: 1, maximum: 60)
        ], required: ["url"])
    }
    
    var isDestructive: Bool { false }
    
    // Maximum response size (50KB)
    private let maxResponseSize = 50_000
    
    func execute(arguments: [String: Any], workingDirectory: String) async throws -> String {
        // Validate URL
        guard let urlString = arguments["url"] as? String else {
            return "Error: Missing required parameter 'url'"
        }
        
        guard let url = URL(string: urlString) else {
            return "Error: Invalid URL '\(urlString)'"
        }
        
        // Security: Only allow HTTP/HTTPS
        guard url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" else {
            return "Error: Only HTTP and HTTPS URLs are allowed"
        }
        
        // Security: Block localhost/private/internal network targets.
        if let blockedReason = blockedNetworkReason(for: url) {
            return "Error: \(blockedReason)"
        }
        
        // Build request
        var request = URLRequest(url: url)
        
        // Set method
        let method = (arguments["method"] as? String)?.uppercased() ?? "GET"
        request.httpMethod = method
        
        // Set headers
        if let headers = arguments["headers"] as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Set body for appropriate methods
        if ["POST", "PUT", "PATCH"].contains(method) {
            if let body = arguments["body"] as? String {
                request.httpBody = body.data(using: .utf8)
                // Set content-type if not already set
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        }
        
        // Set timeout
        let timeout = min(arguments["timeout"] as? Double ?? 30, 60)
        request.timeoutInterval = timeout
        
        // Execute request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return "Error: Invalid response from server"
            }
            
            // Build response output
            var output = "HTTP \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))\n"
            
            // Add headers
            output += "\nHeaders:\n"
            for (key, value) in httpResponse.allHeaderFields {
                output += "  \(key): \(value)\n"
            }
            
            // Process body
            var bodyString: String
            if let text = String(data: data, encoding: .utf8) {
                bodyString = text
            } else if let text = String(data: data, encoding: .isoLatin1) {
                bodyString = text
            } else {
                bodyString = data.base64EncodedString()
                output += "\nBody (base64 encoded):\n"
            }
            
            // Truncate if too large
            if bodyString.count > maxResponseSize {
                bodyString = String(bodyString.prefix(maxResponseSize)) + "\n\n(Response truncated at \(maxResponseSize) characters. Total size: \(data.count) bytes)"
            }
            
            if !output.contains("base64") {
                output += "\nBody:\n\(bodyString)"
            } else {
                output += bodyString
            }
            
            return output
            
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                return "Error: Request timed out after \(Int(timeout)) seconds"
            case .notConnectedToInternet:
                return "Error: No internet connection"
            case .cannotFindHost:
                return "Error: Could not resolve host '\(url.host ?? urlString)'"
            case .cannotConnectToHost:
                return "Error: Could not connect to host"
            default:
                return "Error: Network error - \(error.localizedDescription)"
            }
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Security
    
    /// Returns a human-readable security reason when a URL should be blocked.
    private func blockedNetworkReason(for url: URL) -> String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return "Invalid host"
        }

        // Block obvious local names immediately.
        if host == "localhost" || host == "localhost." || host.hasSuffix(".local") {
            return "Access to localhost or local network hosts is not allowed"
        }

        guard let addresses = resolveHostAddresses(host) else {
            return "Could not resolve host '\(host)'"
        }
        guard !addresses.isEmpty else {
            return "Could not resolve host '\(host)'"
        }

        for address in addresses {
            if isDisallowedAddress(address) {
                return "Access to localhost, private IPs, or internal networks is not allowed"
            }
        }

        return nil
    }

    private enum ResolvedAddress {
        case ipv4(UInt32)
        case ipv6([UInt8])
    }

    /// Resolves hostnames to IP addresses using system DNS resolution.
    private func resolveHostAddresses(_ host: String) -> [ResolvedAddress]? {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0 else { return nil }
        defer { freeaddrinfo(result) }

        var addresses: [ResolvedAddress] = []
        var pointer = result
        while let info = pointer {
            if info.pointee.ai_family == AF_INET,
                let addr = info.pointee.ai_addr?.withMemoryRebound(to: sockaddr_in.self, capacity: 1, {
                    $0.pointee
                })
            {
                addresses.append(.ipv4(UInt32(bigEndian: addr.sin_addr.s_addr)))
            } else if info.pointee.ai_family == AF_INET6,
                let addr6 = info.pointee.ai_addr?.withMemoryRebound(to: sockaddr_in6.self, capacity: 1, {
                    $0.pointee
                })
            {
                let bytes = withUnsafeBytes(of: addr6.sin6_addr.__u6_addr.__u6_addr8) { Array($0) }
                addresses.append(.ipv6(bytes))
            }
            pointer = info.pointee.ai_next
        }

        return addresses
    }

    private func isDisallowedAddress(_ address: ResolvedAddress) -> Bool {
        switch address {
        case .ipv4(let value):
            return isDisallowedIPv4(value)
        case .ipv6(let bytes):
            return isDisallowedIPv6(bytes)
        }
    }

    /// RFC1918, loopback, link-local, multicast, CGNAT, and benchmark ranges.
    private func isDisallowedIPv4(_ value: UInt32) -> Bool {
        let first = (value >> 24) & 0xff
        let second = (value >> 16) & 0xff

        if first == 0 { return true }  // 0.0.0.0/8
        if first == 10 { return true }  // 10.0.0.0/8
        if first == 127 { return true }  // 127.0.0.0/8
        if first == 169 && second == 254 { return true }  // 169.254.0.0/16
        if first == 172 && (16...31).contains(Int(second)) { return true }  // 172.16.0.0/12
        if first == 192 && second == 168 { return true }  // 192.168.0.0/16
        if first == 100 && (64...127).contains(Int(second)) { return true }  // 100.64.0.0/10
        if first == 198 && (second == 18 || second == 19) { return true }  // 198.18.0.0/15
        if first >= 224 { return true }  // Multicast/reserved/broadcast
        return false
    }

    /// Loopback, unique-local, link-local, multicast, unspecified, and IPv4-mapped private.
    private func isDisallowedIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return true }

        // :: (unspecified)
        if bytes.allSatisfy({ $0 == 0 }) { return true }

        // ::1 (loopback)
        if bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 { return true }

        // fc00::/7 (unique-local)
        if (bytes[0] & 0xfe) == 0xfc { return true }

        // fe80::/10 (link-local)
        if bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 { return true }

        // ff00::/8 (multicast)
        if bytes[0] == 0xff { return true }

        // ::ffff:a.b.c.d (IPv4-mapped IPv6)
        let isIPv4Mapped =
            bytes[0...9].allSatisfy { $0 == 0 } && bytes[10] == 0xff && bytes[11] == 0xff
        if isIPv4Mapped {
            let v4 =
                (UInt32(bytes[12]) << 24)
                | (UInt32(bytes[13]) << 16)
                | (UInt32(bytes[14]) << 8)
                | UInt32(bytes[15])
            return isDisallowedIPv4(v4)
        }

        return false
    }
}
