// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0
//
// Copyright (c) 2026 Witt Kung <witt.w.kung@gmail.com>
// All rights reserved.
//
// TTLog: High-performance unified logging and diagnostic telemetry SDK.

import Foundation

/// Output sink interface for dispatching log records (`TTLogSink`).
public protocol TTLogSink: Sendable {
    /// Writes a single log record to the destination.
    func write(record: TTLogRecord)

    /// Flushes any pending buffered log records to the underlying storage or stream.
    func flush()
}
