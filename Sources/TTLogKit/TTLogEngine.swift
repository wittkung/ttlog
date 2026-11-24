// Copyright 2026 MetastudyLine. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0


import Foundation
import os

/// High-performance centralized logging engine (`TTLogEngine`).
public final class TTLogEngine: @unchecked Sendable {
    public static let shared = TTLogEngine()

    private struct State: Sendable {
        var minLevel: TTLogLevel
        var isEnabled: Bool
        var sinks: [TTLogSink]
    }

    private let state: OSAllocatedUnfairLock<State>

    /// Minimum threshold level for active record emission.
    public var level: TTLogLevel {
        get {
            state.withLock { $0.minLevel }
        }
        set {
            state.withLock { $0.minLevel = newValue }
        }
    }

    /// Global master enable flag for logging pipeline.
    public var isEnabled: Bool {
        get {
            state.withLock { $0.isEnabled }
        }
        set {
            state.withLock { $0.isEnabled = newValue }
        }
    }

    private static let environmentLevels: [String: TTLogLevel] = [
        "debug": .debug,
        "info": .info,
        "warning": .warning,
        "warn": .warning,
        "error": .error,
        "quiet": .quiet,
        "off": .quiet,
    ]

    private static func isRunningUnderXCTest(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    }

    private static func resolveInitialLevel(
        from environment: [String: String],
        isRunningTests: Bool
    ) -> TTLogLevel {
        if let configured = environment["TTLOG_LEVEL"] ?? environment["TTZIP_LOG_LEVEL"] {
            return environmentLevels[configured.lowercased()] ?? .info
        }
        return isRunningTests ? .quiet : .info
    }

    private static func resolveDefaultSinks(
        from environment: [String: String],
        isRunningTests: Bool
    ) -> [TTLogSink] {
        var sinks: [TTLogSink] = [
            TTLogOSLogSink(),
            TTLogFileSink.shared,
        ]
        let debugConsole = environment["TTLOG_DEBUG_CONSOLE"] == "1"
            || environment["TTZIP_DEBUG_CONSOLE"] == "1"
        let interactiveConsole = !isRunningTests && isatty(STDOUT_FILENO) != 0
        if debugConsole || interactiveConsole {
            sinks.append(TTLogConsoleSink())
        }
        return sinks
    }

    public init() {
        let env = ProcessInfo.processInfo.environment
        let runningTests = Self.isRunningUnderXCTest(environment: env)
        let initialLevel = Self.resolveInitialLevel(from: env, isRunningTests: runningTests)
        let defaultSinks = Self.resolveDefaultSinks(from: env, isRunningTests: runningTests)

        self.state = OSAllocatedUnfairLock(
            initialState: State(
                minLevel: initialLevel,
                isEnabled: true,
                sinks: defaultSinks
            )
        )
    }

    // MARK: - Sink Management

    /// Appends a new destination sink to the fan-out dispatcher.
    public func addSink(_ sink: TTLogSink) {
        state.withLock { s in
            s.sinks.append(sink)
        }
    }

    /// Replaces current sink collection with the provided list.
    public func setSinks(_ sinks: [TTLogSink]) {
        state.withLock { s in
            s.sinks = sinks
        }
    }

    /// Removes all active sinks.
    public func removeSinks() {
        state.withLock { s in
            s.sinks.removeAll()
        }
    }

    /// Synchronously flushes all active output sinks.
    public func flushSync() {
        let activeSinks = state.withLock { $0.sinks }
        for sink in activeSinks {
            sink.flush()
        }
    }

    // MARK: - Logging Pipeline

    /// Sanitizes message and fans out structured log record to all configured sinks.
    public func log(
        level: TTLogLevel,
        category: TTLogCategory = .general,
        message: String,
        file: String = #file,
        line: UInt = #line
    ) {
        let (shouldLog, activeSinks) = state.withLock { s -> (Bool, [TTLogSink]) in
            guard s.isEnabled else { return (false, []) }
            guard level >= s.minLevel && s.minLevel != .quiet else { return (false, []) }
            return (true, s.sinks)
        }

        guard shouldLog else { return }

        let sanitized = TTLogSanitizer.sanitize(message)
        let fileName = (file as NSString).lastPathComponent
        let record = TTLogRecord(
            timestamp: Date(),
            level: level,
            category: category,
            message: sanitized,
            file: fileName,
            line: line
        )

        for sink in activeSinks {
            sink.write(record: record)
        }
    }
}
