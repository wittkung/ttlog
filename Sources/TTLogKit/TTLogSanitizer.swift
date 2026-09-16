// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0
//
// Copyright (c) 2026 Witt Kung <witt.w.kung@gmail.com>
// All rights reserved.
//
// TTLog: High-performance unified logging and diagnostic telemetry SDK.

import Foundation

/// Industrial zero-trust log sanitizer and sensitive credential redaction engine (`TTLogSanitizer`).
public enum TTLogSanitizer: Sendable {
    public static let redactedMarker = "[REDACTED]"
    public static let redactedKeyMarker = "[REDACTED_PRIVATE_KEY]"

    // Fast rejection scan keywords (lowercased substrings)
    private static let triggerKeywords: [String] = [
        "pass", "pwd", "token", "key", "secret", "bearer", "cred", "auth", "://", "-----begin"
    ]

    private final class RegexRule: @unchecked Sendable {
        let regex: NSRegularExpression
        let template: String

        init(regex: NSRegularExpression, template: String) {
            self.regex = regex
            self.template = template
        }
    }

    private static let rules: [RegexRule] = {
        var list: [RegexRule] = []

        // 1. PEM Private Keys
        if let pemRegex = try? NSRegularExpression(
            pattern: "-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----",
            options: []
        ) {
            list.append(RegexRule(regex: pemRegex, template: redactedKeyMarker))
        }

        // 2. HTTP Authorization Header / Bearer tokens
        if let bearerRegex = try? NSRegularExpression(
            pattern: "(?i)\\b(Bearer\\s+)[A-Za-z0-9\\-._~+/]+=*",
            options: []
        ) {
            list.append(RegexRule(regex: bearerRegex, template: "$1" + redactedMarker))
        }

        // 3. URLs with embedded user:password credentials: https://user:pass@host
        if let urlCredsRegex = try? NSRegularExpression(
            pattern: "([a-zA-Z][a-zA-Z0-9+.-]*://[^:\\s/@]+):([^@\\s/]+)@",
            options: []
        ) {
            list.append(RegexRule(regex: urlCredsRegex, template: "$1:" + redactedMarker + "@"))
        }

        // 4. Key-Value pairs with sensitive names
        let sensitiveKeys = [
            "password", "passwd", "pwd", "passphrase",
            "secret", "app_secret", "client_secret", "shared_secret",
            "api_key", "apikey", "secret_key", "secretkey",
            "private_key", "privkey",
            "access_token", "refresh_token", "auth_token", "tenant_access_token", "user_access_token", "token",
            "credential", "credentials",
            "vault_key", "master_key", "symmetric_key", "aes_key", "encryption_key",
            "aes_hex", "key_hex", "vault_hex"
        ].joined(separator: "|")

        if let kvRegex = try? NSRegularExpression(
            pattern: "(?i)(?<=^|[^a-zA-Z0-9_])(\"?(" + sensitiveKeys + ")\"?\\s*(?:=|:|:=|=>)\\s*)(?:\"([^\"]*)\"|'([^']*)'|`([^`]*)`|([^\\s,;)\\]}\"'>&]+))",
            options: []
        ) {
            list.append(RegexRule(regex: kvRegex, template: "$1" + redactedMarker))
        }

        // 5. Query parameters: (?|&)password=... or (?|&)token=...
        if let queryRegex = try? NSRegularExpression(
            pattern: "(?i)([?&](?:" + sensitiveKeys + ")=)([^&\\s#]+)",
            options: []
        ) {
            list.append(RegexRule(regex: queryRegex, template: "$1" + redactedMarker))
        }

        return list
    }()

    /// Sanitizes message by redacting passwords, secrets, tokens, private keys, and credential URIs.
    public static func sanitize(_ message: String) -> String {
        guard !message.isEmpty else { return message }

        // Fast-path check: if none of the trigger keywords are present, return immediately.
        let lower = message.lowercased()
        var hasTrigger = false
        for kw in triggerKeywords {
            if lower.contains(kw) {
                hasTrigger = true
                break
            }
        }
        guard hasTrigger else {
            return message
        }

        var result = message
        for rule in rules {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = rule.regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: rule.template
            )
        }
        return result
    }
}
