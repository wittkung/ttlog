// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0
//
// Copyright (c) 2026 Witt Kung <witt.w.kung@gmail.com>
// All rights reserved.
//
// TTLog: High-performance unified logging and diagnostic telemetry SDK.

import Foundation

/// Lightweight category-scoped logging facade (`TTLog`).
public struct TTLog: Sendable {
    public let category: TTLogCategory

    public init(_ category: TTLogCategory) {
        self.category = category
    }

    @inline(__always)
    public func debug(
        _ message: @autoclosure () -> String,
        file: String = #file,
        line: UInt = #line
    ) {
        TTLogEngine.shared.log(
            level: .debug,
            category: category,
            message: message(),
            file: file,
            line: line
        )
    }

    @inline(__always)
    public func info(
        _ message: @autoclosure () -> String,
        file: String = #file,
        line: UInt = #line
    ) {
        TTLogEngine.shared.log(
            level: .info,
            category: category,
            message: message(),
            file: file,
            line: line
        )
    }

    @inline(__always)
    public func warning(
        _ message: @autoclosure () -> String,
        file: String = #file,
        line: UInt = #line
    ) {
        TTLogEngine.shared.log(
            level: .warning,
            category: category,
            message: message(),
            file: file,
            line: line
        )
    }

    @inline(__always)
    public func error(
        _ message: @autoclosure () -> String,
        file: String = #file,
        line: UInt = #line
    ) {
        TTLogEngine.shared.log(
            level: .error,
            category: category,
            message: message(),
            file: file,
            line: line
        )
    }
}
