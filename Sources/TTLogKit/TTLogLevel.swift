// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0
//
// Copyright (c) 2026 Witt Kung <witt.w.kung@gmail.com>
// All rights reserved.
//
// TTLog: High-performance unified logging and diagnostic telemetry SDK.

import Foundation

/// Severity level for log records (`TTLogLevel`).
public enum TTLogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case quiet = 4

    public static func < (lhs: TTLogLevel, rhs: TTLogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    /// Uppercase display title for text formatting.
    public var name: String {
        switch self {
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .warning:
            return "WARN"
        case .error:
            return "ERROR"
        case .quiet:
            return "QUIET"
        }
    }
}
