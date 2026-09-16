// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0
//
// Copyright (c) 2026 Witt Kung <witt.w.kung@gmail.com>
// All rights reserved.
//
// TTLog: High-performance unified logging and diagnostic telemetry SDK.

import Foundation

/// File size and retention policy for log rotation (`TTLogRotationPolicy`).
public struct TTLogRotationPolicy: Sendable {
    public var maxFileSizeBytes: UInt64
    public var maxArchiveFiles: Int

    public init(maxFileSizeBytes: UInt64 = 10 * 1024 * 1024, maxArchiveFiles: Int = 5) {
        self.maxFileSizeBytes = maxFileSizeBytes
        self.maxArchiveFiles = maxArchiveFiles
    }

    public static let `default` = TTLogRotationPolicy(maxFileSizeBytes: 10 * 1024 * 1024, maxArchiveFiles: 5)
}

/// Asynchronous rolling log file destination sink (`TTLogFileSink`).
public final class TTLogFileSink: TTLogSink, @unchecked Sendable {
    public static let shared = TTLogFileSink()

    private static let queueSpecificKey = DispatchSpecificKey<Void>()
    private let queue: DispatchQueue

    private let rotationPolicy: TTLogRotationPolicy
    private let logDirectory: URL
    private let primaryLogFileURL: URL
    private let filePrefix: String
    private var fileHandle: FileHandle?
    private var currentFileSize: UInt64 = 0

    public var logFilePath: String {
        return primaryLogFileURL.path
    }

    public var logDirectoryPath: String {
        return logDirectory.path
    }

    public init(
        logDirectory: URL? = nil,
        filePrefix: String = "ttlog",
        subsystem: String = "default",
        rotationPolicy: TTLogRotationPolicy = .default
    ) {
        self.filePrefix = filePrefix
        self.rotationPolicy = rotationPolicy

        let queue = DispatchQueue(label: "com.metastudyline.ttlog.logfilesink.\(filePrefix)", qos: .utility)
        queue.setSpecific(key: Self.queueSpecificKey, value: ())
        self.queue = queue

        if let customDir = logDirectory {
            self.logDirectory = customDir
        } else {
            let baseDir: URL
            if let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
                baseDir = libraryDir
            } else {
                baseDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
            }
            let subPath = subsystem == "default" ? "Logs/TTLog" : "Logs/\(subsystem)"
            self.logDirectory = baseDir.appendingPathComponent(subPath, isDirectory: true)
        }

        self.primaryLogFileURL = self.logDirectory.appendingPathComponent("\(filePrefix).log")

        self.queue.sync {
            self.prepareDirectoryAndOpenFile()
        }
    }

    public convenience init(customLogDirectory: URL?) {
        self.init(logDirectory: customLogDirectory, filePrefix: "ttlog", subsystem: "default", rotationPolicy: .default)
    }

    deinit {
        flushSync()
        try? fileHandle?.close()
    }

    // MARK: - Public API

    /// Appends formatted string asynchronously onto dedicated serial queue.
    public func write(_ string: String) {
        queue.async { [self] in
            self.appendInternal(string)
        }
    }

    /// Appends a structured log record to the log file.
    public func write(record: TTLogRecord) {
        let timeStr = record.timestamp.formatted(.iso8601)
        let fileLogLine = "[\(timeStr)] [\(record.level.name)] [\(record.category.rawValue)] [\(record.file):\(record.line)] \(record.message)\n"
        write(fileLogLine)
    }

    /// Flushes log file buffers to disk asynchronously or synchronously depending on caller queue context.
    public func flush() {
        flushSync()
    }

    /// Synchronously flushes log file buffers to disk with deadlock prevention.
    public func flushSync() {
        if DispatchQueue.getSpecific(key: Self.queueSpecificKey) != nil {
            self.flushInternal()
        } else {
            queue.sync {
                self.flushInternal()
            }
        }
    }

    // MARK: - Internal Engine

    private func prepareDirectoryAndOpenFile() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logDirectory.path) {
            try? fm.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: nil)
        }

        if !fm.fileExists(atPath: primaryLogFileURL.path) {
            fm.createFile(atPath: primaryLogFileURL.path, contents: nil, attributes: nil)
            currentFileSize = 0
        } else {
            if let attrs = try? fm.attributesOfItem(atPath: primaryLogFileURL.path),
               let size = attrs[.size] as? UInt64 {
                currentFileSize = size
            } else {
                currentFileSize = 0
            }
        }

        fileHandle = try? FileHandle(forWritingTo: primaryLogFileURL)
        if let handle = fileHandle {
            _ = try? handle.seekToEnd()
        }
    }

    private func appendInternal(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        let writeLength = UInt64(data.count)

        if currentFileSize + writeLength > rotationPolicy.maxFileSizeBytes {
            rotateFilesInternal()
        }

        if fileHandle == nil {
            prepareDirectoryAndOpenFile()
        }

        guard let handle = fileHandle else { return }
        do {
            try handle.write(contentsOf: data)
            currentFileSize += writeLength
        } catch {
            // Fallback: try reopening once on failure
            try? handle.close()
            fileHandle = nil
            prepareDirectoryAndOpenFile()
            try? fileHandle?.write(contentsOf: data)
            currentFileSize += writeLength
        }
    }

    private func rotateFilesInternal() {
        try? fileHandle?.synchronize()
        try? fileHandle?.close()
        fileHandle = nil

        let fm = FileManager.default
        let maxCount = rotationPolicy.maxArchiveFiles

        // 1. Remove the oldest backup if it exists (e.g. ttlog.5.log)
        let oldestBackup = logDirectory.appendingPathComponent("\(filePrefix).\(maxCount).log")
        if fm.fileExists(atPath: oldestBackup.path) {
            try? fm.removeItem(at: oldestBackup)
        }

        // 2. Shift older backups down: ttlog.4.log -> ttlog.5.log, ..., ttlog.1.log -> ttlog.2.log
        if maxCount > 1 {
            for index in stride(from: maxCount - 1, through: 1, by: -1) {
                let src = logDirectory.appendingPathComponent("\(filePrefix).\(index).log")
                let dst = logDirectory.appendingPathComponent("\(filePrefix).\(index + 1).log")
                if fm.fileExists(atPath: src.path) {
                    try? fm.moveItem(at: src, to: dst)
                }
            }
        }

        // 3. Move active log to ttlog.1.log
        let firstBackup = logDirectory.appendingPathComponent("\(filePrefix).1.log")
        if fm.fileExists(atPath: primaryLogFileURL.path) {
            try? fm.moveItem(at: primaryLogFileURL, to: firstBackup)
        }

        // 4. Create fresh active file
        fm.createFile(atPath: primaryLogFileURL.path, contents: nil, attributes: nil)
        currentFileSize = 0
        fileHandle = try? FileHandle(forWritingTo: primaryLogFileURL)
    }

    private func flushInternal() {
        try? fileHandle?.synchronize()
    }
}
