// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0
//
// Copyright (c) 2026 Witt Kung <witt.w.kung@gmail.com>
// All rights reserved.
//
// TTLog: High-performance unified logging and diagnostic telemetry SDK.

import Foundation
import os

/// Apple Unified Logging destination sink (`TTLogOSLogSink`).
public final class TTLogOSLogSink: TTLogSink, @unchecked Sendable {
    public let subsystem: String
    private let cachedLoggers: OSAllocatedUnfairLock<[String: os.Logger]>

    public init(subsystem: String = "com.metastudyline.ttlog") {
        self.subsystem = subsystem
        self.cachedLoggers = OSAllocatedUnfairLock(initialState: [:])
    }

    private func logger(for category: TTLogCategory) -> os.Logger {
        let key = category.rawValue
        return cachedLoggers.withLock { cache in
            if let existing = cache[key] {
                return existing
            }
            let created = os.Logger(subsystem: subsystem, category: key)
            cache[key] = created
            return created
        }
    }

    public func write(record: TTLogRecord) {
        let osLogger = logger(for: record.category)
        switch record.level {
        case .debug:
            osLogger.debug("\(record.message, privacy: .public)")
        case .info:
            osLogger.info("\(record.message, privacy: .public)")
        case .warning:
            osLogger.warning("\(record.message, privacy: .public)")
        case .error:
            osLogger.error("\(record.message, privacy: .public)")
        case .quiet:
            break
        }
    }

    public func flush() {
        // os.Logger handles buffer flushes asynchronously at the kernel/daemon level.
    }
}
