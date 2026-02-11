//
//  FetchTool.swift
//  AI Chat
//
//  Created by Humlex on 2/11/26.
//

import Foundation

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
        
        // Security: Block private/local addresses
        if isPrivateOrLocalURL(url) {
            return "Error: Access to localhost, private IPs, or internal networks is not allowed"
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
    
    /// Check if URL points to private/local addresses that should be blocked.
    private func isPrivateOrLocalURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        
        // Block localhost variants
        if host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "0.0.0.0" {
            return true
        }
        
        // Block private IP ranges
        if isPrivateIP(host) {
            return true
        }
        
        // Block common internal hostnames
        let blockedHosts = [
            "internal", "intranet", "local", "private",
            "192.168", "10.", "172.16", "172.17", "172.18", "172.19",
            "172.20", "172.21", "172.22", "172.23", "172.24",
            "172.25", "172.26", "172.27", "172.28", "172.29",
            "172.30", "172.31"
        ]
        
        for blocked in blockedHosts {
            if host.contains(blocked) {
                return true
            }
        }
        
        return false
    }
    
    /// Check if host string is a private IP address.
    private func isPrivateIP(_ host: String) -> Bool {
        // Check for IPv4 private ranges
        let ipv4PrivatePatterns = [
            "^127\\.",              // Loopback
            "^10\\.",               // Class A private
            "^172\\.(1[6-9]|2[0-9]|3[0-1])\\.",  // Class B private
            "^192\\.168\\.",        // Class C private
            "^169\\.254\\."         // Link-local
        ]
        
        for pattern in ipv4PrivatePatterns {
            if host.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        // Check for IPv6 loopback
        if host == "::1" || host == "::" || host.hasPrefix("fe80::") {
            return true
        }
        
        return false
    }
}
