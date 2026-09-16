// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0
//
// Copyright (c) 2026 Witt Kung <witt.w.kung@gmail.com>
// All rights reserved.
//
// TTLog: High-performance unified logging and diagnostic telemetry SDK.

import Foundation

/// Terminal standard output destination sink (`TTLogConsoleSink`).
public final class TTLogConsoleSink: TTLogSink, @unchecked Sendable {
    public init() {}

    public func write(record: TTLogRecord) {
        let line = "[\(record.file):\(record.line)] [\(record.category.rawValue)] \(record.message)\n"
        fputs(line, stdout)
        fflush(stdout)
    }

    public func flush() {
        fflush(stdout)
    }
}
