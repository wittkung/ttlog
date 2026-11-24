// Copyright 2026 MetastudyLine. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0


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

    private func archiveURL(forGeneration generation: Int) -> URL {
        logDirectory.appendingPathComponent("\(filePrefix).\(generation).log")
    }

    private func closeActiveFileHandle() {
        guard let handle = fileHandle else { return }
        try? handle.synchronize()
        try? handle.close()
        fileHandle = nil
    }

    private func moveFileIfPresent(from source: URL, to destination: URL, using fm: FileManager) {
        guard fm.fileExists(atPath: source.path) else { return }
        try? fm.moveItem(at: source, to: destination)
    }

    private func shiftArchiveGenerations(using fm: FileManager) {
        let maxCount = rotationPolicy.maxArchiveFiles
        let oldestBackup = archiveURL(forGeneration: maxCount)
        if fm.fileExists(atPath: oldestBackup.path) {
            try? fm.removeItem(at: oldestBackup)
        }

        guard maxCount > 1 else { return }
        for generation in stride(from: maxCount - 1, through: 1, by: -1) {
            moveFileIfPresent(
                from: archiveURL(forGeneration: generation),
                to: archiveURL(forGeneration: generation + 1),
                using: fm
            )
        }
    }

    private func openFreshPrimaryFile(using fm: FileManager) {
        fm.createFile(atPath: primaryLogFileURL.path, contents: nil, attributes: nil)
        currentFileSize = 0
        fileHandle = try? FileHandle(forWritingTo: primaryLogFileURL)
    }

    private func rotateFilesInternal() {
        closeActiveFileHandle()
        let fm = FileManager.default
        shiftArchiveGenerations(using: fm)
        moveFileIfPresent(from: primaryLogFileURL, to: archiveURL(forGeneration: 1), using: fm)
        openFreshPrimaryFile(using: fm)
    }

    private func flushInternal() {
        try? fileHandle?.synchronize()
    }
}
