// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0
//
// Copyright (c) 2026 Witt Kung <witt.w.kung@gmail.com>
// All rights reserved.
//
// TTLog: High-performance unified logging and diagnostic telemetry SDK.

import Foundation

/// Extensible logging category identifier (`TTLogCategory`).
///
/// Implemented as an open RawRepresentable struct following Apple standard platform conventions
/// (`Notification.Name`, `URLResourceKey`), allowing cross-module static extension.
public struct TTLogCategory: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

extension TTLogCategory {
    /// General subsystem fallback category.
    public static let general = TTLogCategory(rawValue: "general")
}
