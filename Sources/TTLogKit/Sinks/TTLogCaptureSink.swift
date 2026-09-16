// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0
//
// Copyright (c) 2026 Witt Kung <witt.w.kung@gmail.com>
// All rights reserved.
//
// TTLog: High-performance unified logging and diagnostic telemetry SDK.

import Foundation
import os

/// In-memory test diagnostic log capture sink (`TTLogCaptureSink`).
public final class TTLogCaptureSink: TTLogSink, @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<[TTLogRecord]>
    private let maxCapacity: Int

    public init(maxCapacity: Int = 2000) {
        self.maxCapacity = maxCapacity
        self.state = OSAllocatedUnfairLock(initialState: [])
    }

    /// Snapshot array of currently captured log records.
    public var records: [TTLogRecord] {
        return state.withLock { $0 }
    }

    /// Clears all recorded entries from memory buffer.
    public func clear() {
        state.withLock { $0.removeAll(keepingCapacity: true) }
    }

    public func write(record: TTLogRecord) {
        state.withLock { buf in
            if buf.count >= maxCapacity {
                buf.removeFirst(min(100, buf.count))
            }
            buf.append(record)
        }
    }

    public func flush() {
        // No-op for in-memory buffer.
    }

    /// Formats and prints currently captured logs to standard output upon test assertion failure.
    public func dumpOnFailure(testName: String = "Test") {
        let buffer = records
        guard !buffer.isEmpty else { return }

        fputs("\n==========================================================================================\n", stdout)
        fputs("🚨 [TTLogCaptureSink Log Dump on Failure] Test '\(testName)' execution trace (\(buffer.count) entries)\n", stdout)
        fputs("==========================================================================================\n", stdout)
        for entry in buffer {
            fputs(" [\(entry.level.name)] [\(entry.category.rawValue)] [\(entry.file):\(entry.line)] \(entry.message)\n", stdout)
        }
        fputs("==========================================================================================\n\n", stdout)
        fflush(stdout)
    }
}
