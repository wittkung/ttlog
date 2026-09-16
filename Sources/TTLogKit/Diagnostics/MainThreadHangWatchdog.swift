// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0
//
// Copyright (c) 2026 Witt Kung <witt.w.kung@gmail.com>
// All rights reserved.
//
// TTLog: High-performance unified logging and diagnostic telemetry SDK.

import Foundation
import os

/// Dedicated background watchdog thread monitoring main thread responsiveness (`MainThreadHangWatchdog`).
public final class MainThreadHangWatchdog: @unchecked Sendable {
    public static let shared = MainThreadHangWatchdog()

    private static let hangCategory = TTLogCategory(rawValue: "hang")

    private struct WatchdogState: Sendable {
        var isRunning: Bool = false
        var lastPingResponseUptime: TimeInterval = 0
        var lastLoggedHangUptime: TimeInterval = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: WatchdogState())
    private var watchdogThread: Thread?

    public init() {}

    deinit {
        stop()
    }

    // MARK: - Lifecycle Control

    /// Starts the independent daemon watchdog thread.
    public func start() {
        let shouldStart = state.withLock { s -> Bool in
            if s.isRunning { return false }
            s.isRunning = true
            s.lastPingResponseUptime = ProcessInfo.processInfo.systemUptime
            s.lastLoggedHangUptime = 0
            return true
        }

        guard shouldStart else { return }

        let thread = Thread { [weak self] in
            self?.runWatchdogLoop()
        }
        thread.name = "com.metastudyline.ttlog.hang-watchdog"
        thread.qualityOfService = .utility
        self.watchdogThread = thread
        thread.start()

        TTLogEngine.shared.log(
            level: .info,
            category: Self.hangCategory,
            message: "MainThreadHangWatchdog daemon thread started."
        )
    }

    /// Stops the watchdog thread.
    public func stop() {
        state.withLock { s in
            s.isRunning = false
        }
        watchdogThread?.cancel()
        watchdogThread = nil
    }

    // MARK: - Event Loop

    private func runWatchdogLoop() {
        while true {
            let isRunning = state.withLock { $0.isRunning }
            if !isRunning || Thread.current.isCancelled {
                break
            }

            Thread.sleep(forTimeInterval: 0.5)

            let now = ProcessInfo.processInfo.systemUptime
            let (lastPingResponse, lastLoggedHang, running) = state.withLock {
                ($0.lastPingResponseUptime, $0.lastLoggedHangUptime, $0.isRunning)
            }

            guard running && !Thread.current.isCancelled else { break }

            let elapsed = now - lastPingResponse
            if elapsed > 2.0 {
                // Throttle repeated hang reports to avoid log flooding
                if now - lastLoggedHang >= 2.0 {
                    state.withLock { $0.lastLoggedHangUptime = now }
                    let hangMessage = "[FATAL HANG] Main thread RunLoop unresponsive for \(String(format: "%.2f", elapsed))s (threshold: 2.00s)!"
                    TTLogEngine.shared.log(level: .error, category: Self.hangCategory, message: hangMessage)
                    TTLogFileSink.shared.flushSync()
                }
            }

            // Ping the main thread asynchronously
            let pingDispatchedAt = now
            DispatchQueue.main.async { [weak self] in
                let pingResponseNow = ProcessInfo.processInfo.systemUptime
                let latency = pingResponseNow - pingDispatchedAt
                if latency > 1.5 {
                    let mainStack = Thread.callStackSymbols.joined(separator: "\n")
                    let resumeMessage = "[HANG RECOVERED] Main thread resumed after \(String(format: "%.2f", latency))s blockage! Main thread call stack:\n\(mainStack)"
                    TTLogEngine.shared.log(level: .warning, category: Self.hangCategory, message: resumeMessage)
                    TTLogFileSink.shared.flushSync()
                }
                self?.state.withLock { s in
                    s.lastPingResponseUptime = pingResponseNow
                }
            }
        }
    }
}
