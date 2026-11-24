// Copyright 2026 MetastudyLine. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause OR Apache-2.0


import XCTest
import TTLogKit

final class TTLogKitTests: XCTestCase {

    // MARK: - 1. Level Comparison Tests

    func testLogLevelComparison() {
        XCTAssertLessThan(TTLogLevel.debug, TTLogLevel.info)
        XCTAssertLessThan(TTLogLevel.info, TTLogLevel.warning)
        XCTAssertLessThan(TTLogLevel.warning, TTLogLevel.error)
        XCTAssertLessThan(TTLogLevel.error, TTLogLevel.quiet)

        XCTAssertEqual(TTLogLevel.debug.name, "DEBUG")
        XCTAssertEqual(TTLogLevel.info.name, "INFO")
        XCTAssertEqual(TTLogLevel.warning.name, "WARN")
        XCTAssertEqual(TTLogLevel.error.name, "ERROR")
        XCTAssertEqual(TTLogLevel.quiet.name, "QUIET")
    }

    // MARK: - 2. Sanitizer Redaction Tests

    func testSanitizerRedactsSensitivePatterns() {
        // PEM Private Key
        let pemKey = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEA0m4w1r2...
        -----END RSA PRIVATE KEY-----
        """
        let sanitizedPem = TTLogSanitizer.sanitize(pemKey)
        XCTAssertEqual(sanitizedPem, TTLogSanitizer.redactedKeyMarker)

        // Bearer Token
        let authHeader = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.t-ID"
        let sanitizedAuth = TTLogSanitizer.sanitize(authHeader)
        XCTAssertEqual(sanitizedAuth, "Authorization: Bearer [REDACTED]")

        // URL embedded credentials
        let urlWithCreds = "Connecting to https://admin:supersecret@api.internal:8080/v1"
        let sanitizedUrl = TTLogSanitizer.sanitize(urlWithCreds)
        XCTAssertEqual(sanitizedUrl, "Connecting to https://admin:[REDACTED]@api.internal:8080/v1")

        // Key-Value sensitive credentials
        let sensitiveKv = "db connection: password = \"mypassword123\" and client_secret: 'top_secret'"
        let sanitizedKv = TTLogSanitizer.sanitize(sensitiveKv)
        XCTAssertTrue(sanitizedKv.contains("password = [REDACTED]"))
        XCTAssertTrue(sanitizedKv.contains("client_secret: [REDACTED]"))
        XCTAssertFalse(sanitizedKv.contains("mypassword123"))
        XCTAssertFalse(sanitizedKv.contains("top_secret"))

        // Query parameters
        let queryUrl = "https://example.com/callback?token=sec12345&user=witt"
        let sanitizedQuery = TTLogSanitizer.sanitize(queryUrl)
        XCTAssertTrue(sanitizedQuery.contains("token=[REDACTED]"))
        XCTAssertTrue(sanitizedQuery.contains("user=witt"))

        // Normal log message fast-path
        let normalMsg = "Worker successfully processed 1024 tasks without errors"
        XCTAssertEqual(TTLogSanitizer.sanitize(normalMsg), normalMsg)
    }

    // MARK: - 3. Engine Dispatch Tests

    func testLogEngineDispatchesToSinks() {
        let engine = TTLogEngine()
        let captureSink = TTLogCaptureSink()
        engine.setSinks([captureSink])
        engine.level = .info
        engine.isEnabled = true

        // Debug should be filtered out by level threshold
        engine.log(level: .debug, message: "Debug trace")
        XCTAssertEqual(captureSink.records.count, 0)

        // Info should pass through
        engine.log(level: .info, category: .general, message: "Engine started")
        XCTAssertEqual(captureSink.records.count, 1)
        XCTAssertEqual(captureSink.records.first?.message, "Engine started")
        XCTAssertEqual(captureSink.records.first?.level, .info)

        // Error with credential should be sanitized
        engine.log(level: .error, category: TTLogCategory(rawValue: "auth"), message: "Auth failed password=secret")
        XCTAssertEqual(captureSink.records.count, 2)
        XCTAssertTrue(captureSink.records.last?.message.contains("[REDACTED]") == true)

        // Disable engine and ensure logs are suppressed
        engine.isEnabled = false
        engine.log(level: .error, message: "Suppressed error")
        XCTAssertEqual(captureSink.records.count, 2)
    }

    // MARK: - 4. File Sink Rotation & Sync Tests

    func testFileSinkRotationAndSync() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TTLogFileSinkTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let policy = TTLogRotationPolicy(maxFileSizeBytes: 120, maxArchiveFiles: 3)
        let fileSink = TTLogFileSink(logDirectory: tempDir, filePrefix: "test", rotationPolicy: policy)

        for i in 0..<15 {
            fileSink.write("Line \(i): This message is long enough to trigger file rotation.\n")
        }
        fileSink.flushSync()

        let activeLog = tempDir.appendingPathComponent("test.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: activeLog.path))

        let backupLog1 = tempDir.appendingPathComponent("test.1.log")
        let backupLog2 = tempDir.appendingPathComponent("test.2.log")
        let backupLog3 = tempDir.appendingPathComponent("test.3.log")
        let backupLog4 = tempDir.appendingPathComponent("test.4.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupLog1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupLog2.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupLog3.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupLog4.path))
    }

    // MARK: - 5. Capture Sink Tests

    func testCaptureSinkCapturesAndClears() {
        let capture = TTLogCaptureSink(maxCapacity: 5)
        for i in 0..<10 {
            capture.write(
                record: TTLogRecord(
                    level: .info,
                    message: "Log \(i)",
                    file: "TTLogKitTests.swift",
                    line: UInt(i)
                )
            )
        }

        XCTAssertLessThanOrEqual(capture.records.count, 5)
        XCTAssertFalse(capture.records.isEmpty)

        // Exercise failure dump API
        capture.dumpOnFailure(testName: "testCaptureSinkCapturesAndClears")

        // Clear buffer
        capture.clear()
        XCTAssertEqual(capture.records.count, 0)
    }

    // MARK: - 6. Watchdog Concurrency Safety Tests

    func testMainThreadHangWatchdogThreadSafety() {
        let watchdog = MainThreadHangWatchdog()
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            if index.isMultiple(of: 2) {
                watchdog.start()
            } else {
                watchdog.stop()
            }
        }
        watchdog.stop()
    }

    // MARK: - 7. Control Character & ANSI Sanitization Tests (CWE-117, CWE-150)

    func testSanitizerEscapesControlCharactersAndAnsi() {
        // 1. CRLF Injection (CWE-117)
        let crlfInjection = "User 'attacker' logged in\r\n[CRITICAL] System integrity failed\r\n"
        let sanitizedCrlf = TTLogSanitizer.sanitize(crlfInjection)
        XCTAssertEqual(
            sanitizedCrlf,
            "User 'attacker' logged in\\r\\n[CRITICAL] System integrity failed\\r\\n"
        )
        XCTAssertFalse(sanitizedCrlf.contains("\r"))
        XCTAssertFalse(sanitizedCrlf.contains("\n"))

        // 2. ANSI Terminal Control Sequences (CWE-150)
        let ansiSequence = "Status: OK\u{001B}[2J\u{001B}[H\u{001B}[31mInjected Red\u{001B}[0m"
        let sanitizedAnsi = TTLogSanitizer.sanitize(ansiSequence)
        XCTAssertEqual(sanitizedAnsi, "Status: OK\\e[2J\\e[H\\e[31mInjected Red\\e[0m")
        XCTAssertFalse(sanitizedAnsi.contains("\u{001B}"))

        // 3. NULL Byte injection
        let nullByteMsg = "root\0admin_override"
        let sanitizedNull = TTLogSanitizer.sanitize(nullByteMsg)
        XCTAssertEqual(sanitizedNull, "root\\0admin_override")
        XCTAssertFalse(sanitizedNull.contains("\0"))

        // 4. Tab escaping
        let tabMsg = "Column1\tColumn2\tColumn3"
        let sanitizedTab = TTLogSanitizer.sanitize(tabMsg)
        XCTAssertEqual(sanitizedTab, "Column1\\tColumn2\\tColumn3")
        XCTAssertFalse(sanitizedTab.contains("\t"))

        // 5. C0 Control characters (Bell, Backspace, DEL)
        let c0Msg = "Alert\u{0007}Backspace\u{0008}Delete\u{007F}"
        let sanitizedC0 = TTLogSanitizer.sanitize(c0Msg)
        XCTAssertEqual(sanitizedC0, "Alert\\x07Backspace\\x08Delete\\x7F")

        // 6. Normal UTF-8 text with multi-byte characters and emojis (zero corruption)
        let normalMsg = "Task 42 succeeded: 部署成功 🚀, elapsed: 12ms."
        let sanitizedNormal = TTLogSanitizer.sanitize(normalMsg)
        XCTAssertEqual(sanitizedNormal, normalMsg)
    }

    func testSanitizerEscapesCombinedCredentialsAndControlInjections() {
        let maliciousPayload = "User auth: password = \"secret456\"\r\n[CRITICAL] Fake root event\u{001B}[2J"
        let sanitized = TTLogSanitizer.sanitize(maliciousPayload)

        // Verifies credential redaction occurred
        XCTAssertTrue(sanitized.contains("password = [REDACTED]"))
        XCTAssertFalse(sanitized.contains("secret456"))

        // Verifies control characters and ANSI codes were escaped
        XCTAssertTrue(sanitized.contains("\\r\\n[CRITICAL] Fake root event\\e[2J"))
        XCTAssertFalse(sanitized.contains("\r"))
        XCTAssertFalse(sanitized.contains("\n"))
        XCTAssertFalse(sanitized.contains("\u{001B}"))
    }

    func testDirectEscapeControlCharactersAPI() {
        XCTAssertEqual(TTLogSanitizer.escapeControlCharacters(""), "")
        XCTAssertEqual(
            TTLogSanitizer.escapeControlCharacters("Simple ASCII string with no escapes"),
            "Simple ASCII string with no escapes"
        )
        XCTAssertEqual(
            TTLogSanitizer.escapeControlCharacters("Line1\rLine2\nLine3\tTab"),
            "Line1\\rLine2\\nLine3\\tTab"
        )
    }
}

