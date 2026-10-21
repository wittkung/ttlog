// Copyright 2026 MetastudyLine. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0


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
