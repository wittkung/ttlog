// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0
//
// Copyright (c) 2026 Witt Kung <witt.w.kung@gmail.com>
// All rights reserved.
//
// TTLog: High-performance unified logging and diagnostic telemetry SDK.

import Foundation

/// Immutable record capturing a single log event (`TTLogRecord`).
public struct TTLogRecord: Sendable {
    public let timestamp: Date
    public let level: TTLogLevel
    public let category: TTLogCategory
    public let message: String
    public let file: String
    public let line: UInt

    public init(
        timestamp: Date = Date(),
        level: TTLogLevel,
        category: TTLogCategory = .general,
        message: String,
        file: String,
        line: UInt
    ) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.file = file
        self.line = line
    }
}
