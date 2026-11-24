// Copyright 2026 MetastudyLine. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0


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

    // Precomputed hex lookup table for C0/C1 control characters
    private static let hexAlphabet: [UnicodeScalar] = Array("0123456789ABCDEF".unicodeScalars)

    @inlinable
    static func isControlCharacter(_ scalar: UnicodeScalar) -> Bool {
        let val = scalar.value
        return val < 0x20 || (val >= 0x7F && val <= 0x9F)
    }

    /// Escapes control characters, CRLF line injections (CWE-117), and ANSI escape sequences (CWE-150).
    ///
    /// - Fast path: returns the original `message` if no C0/C1 control characters are present (zero heap allocation).
    /// - Escapes `\r` to `\r`, `\n` to `\n`, `\t` to `\t`, `\0` to `\0`, `\u{001B}` (ESC) to `\e`.
    /// - Escapes remaining C0/C1 control characters (< 0x20, 0x7F...0x9F) to `\xHH`.
    public static func escapeControlCharacters(_ message: String) -> String {
        guard !message.isEmpty else { return message }

        // Fast-path: if message contains no C0 or C1 control characters, return immediately.
        guard message.unicodeScalars.contains(where: { isControlCharacter($0) }) else {
            return message
        }

        var output = ""
        output.reserveCapacity(message.utf8.count + 16)

        for scalar in message.unicodeScalars {
            switch scalar.value {
            case 0x00: // NUL
                output.append("\\0")
            case 0x09: // Horizontal Tab (\t)
                output.append("\\t")
            case 0x0A: // Line Feed (\n)
                output.append("\\n")
            case 0x0D: // Carriage Return (\r)
                output.append("\\r")
            case 0x1B: // Escape (ESC)
                output.append("\\e")
            case 0x01...0x08, 0x0B...0x0C, 0x0E...0x1A, 0x1C...0x1F, 0x7F...0x9F:
                let high = Int((scalar.value >> 4) & 0x0F)
                let low = Int(scalar.value & 0x0F)
                output.append("\\x")
                output.unicodeScalars.append(hexAlphabet[high])
                output.unicodeScalars.append(hexAlphabet[low])
            default:
                output.unicodeScalars.append(scalar)
            }
        }

        return output
    }

    /// Sanitizes message by redacting passwords, secrets, tokens, private keys, credential URIs,
    /// and escaping control characters and ANSI terminal codes (CWE-117, CWE-150).
    public static func sanitize(_ message: String) -> String {
        guard !message.isEmpty else { return message }

        var result = message

        // 1. Redact credentials if trigger keywords are present
        let lower = result.lowercased()
        var hasTrigger = false
        for kw in triggerKeywords {
            if lower.contains(kw) {
                hasTrigger = true
                break
            }
        }

        if hasTrigger {
            for rule in rules {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = rule.regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: range,
                    withTemplate: rule.template
                )
            }
        }

        // 2. Escape control characters and terminal escape sequences (CWE-117, CWE-150)
        return escapeControlCharacters(result)
    }
}

