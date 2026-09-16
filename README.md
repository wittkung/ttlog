# TTLogKit

High-performance unified logging and diagnostic telemetry SDK in pure Swift 6.0 with strict concurrency and zero external dependencies.

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20%7C%20iOS%20%7C%20watchOS%20%7C%20tvOS%20%7C%20visionOS-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-Apache%202.0%20%2F%20BSD--3--Clause-green.svg)](LICENSE-APACHE)

---

## Key Architectural Principles

- **Zero External Dependencies**: Implemented strictly using Apple `Foundation` and `os` frameworks.
- **Swift 6 Strict Concurrency**: 100% compliant with Swift 6 strict concurrency (`Sendable`, `OSAllocatedUnfairLock`), zero data races.
- **Zero-Trust Credential Sanitizer**: Automatically detects and redacts PEM private keys, bearer tokens, embedded HTTP basic auth URLs, and sensitive key-value query parameters prior to fan-out.
- **Multi-Sink Fan-Out Architecture**: Pluggable `TTLogSink` pipeline supporting `os.Logger`, non-blocking rolling file rotation, terminal standard output, and in-memory test capture sinks.
- **Main Thread Hang Watchdog**: Independent daemon thread continuously monitoring main RunLoop responsiveness with automatic stack trace diagnostics.

---

## Installation

Add `TTLogKit` to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/wittkung/ttlog.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "TTLogKit", package: "ttlog")
        ]
    )
]
```

---

## Quick Start

### Basic Category Logging

```swift
import TTLogKit

// Define subsystem category
extension TTLogCategory {
    static let network = TTLogCategory(rawValue: "network")
}

let logger = TTLog(.network)

// Autoclosure evaluation ensures zero overhead when severity is below active threshold
logger.debug("Establishing socket connection...")
logger.info("Connection established to host: example.com")
logger.warning("High latency detected: 450ms")
logger.error("Connection dropped abruptly")
```

### Credential Redaction

Sensitive patterns are sanitized before records reach sinks:

```swift
let logger = TTLog(.general)

// Passwords, tokens, and private keys are automatically redacted
logger.info("Connecting with password=super_secret_token")
// Emits: Connecting with password=[REDACTED]

logger.info("Request auth: Bearer eyJhbGciOiJIUzI1Ni...")
// Emits: Request auth: Bearer [REDACTED]
```

### Configurable Sinks & Engine Setup

```swift
import TTLogKit

// Configure global engine level
TTLogEngine.shared.level = .debug

// Register custom sinks
let customCaptureSink = TTLogCaptureSink(maxCapacity: 1000)
TTLogEngine.shared.addSink(customCaptureSink)

// Rolling file sink with custom rotation policy
let fileSink = TTLogFileSink(
    filePrefix: "myapp",
    subsystem: "MyApp",
    rotationPolicy: TTLogRotationPolicy(
        maxFileSizeBytes: 5 * 1024 * 1024, // 5 MB
        maxArchiveFiles: 3
    )
)
TTLogEngine.shared.addSink(fileSink)
```

### Main Thread Hang Watchdog

```swift
import TTLogKit

// Launch background hang detection daemon
MainThreadHangWatchdog.shared.start()

// Stop when terminating or tearing down
MainThreadHangWatchdog.shared.stop()
```

---

## License

TTLogKit is dual-licensed under:
- **Apache License, Version 2.0** ([LICENSE-APACHE](LICENSE-APACHE))
- **BSD 3-Clause License** ([LICENSE-BSD](LICENSE-BSD))

Copyright (c) 2026 Witt Kung <witt.w.kung@gmail.com>. All rights reserved.
