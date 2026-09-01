// TestSupport.swift
// Minimal test infrastructure compatible with swift test (no XCTest/Testing dependency needed).
// Uses Swift's built-in XCTest via the test target's implicit linkage when available.

import Foundation

// Re-export via a simple assertion wrapper so tests are framework-agnostic.
// Swift Package Manager test targets automatically link against XCTest on Apple platforms
// when the test target is declared without explicit framework dependencies.

// We use a custom lightweight runner as fallback.

struct TestRunner {
    static var passed = 0
    static var failed = 0
    static var failures: [String] = []

    static func assert(_ condition: Bool, _ message: String,
                        file: StaticString = #file, line: UInt = #line) {
        if condition {
            passed += 1
        } else {
            failed += 1
            let loc = "\(file):\(line)"
            failures.append("FAIL: \(message) [\(loc)]")
        }
    }

    static func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "",
                                           file: StaticString = #file, line: UInt = #line) {
        assert(a == b, message.isEmpty ? "Expected \(a) == \(b)" : message, file: file, line: line)
    }

    static func assertLessThan<T: Comparable>(_ a: T, _ b: T, _ message: String = "",
                                              file: StaticString = #file, line: UInt = #line) {
        assert(a < b, message.isEmpty ? "Expected \(a) < \(b)" : message, file: file, line: line)
    }

    static func assertGreaterThan<T: Comparable>(_ a: T, _ b: T, _ message: String = "",
                                                  file: StaticString = #file, line: UInt = #line) {
        assert(a > b, message.isEmpty ? "Expected \(a) > \(b)" : message, file: file, line: line)
    }

    static func printResults() {
        print("\n=== Test Results ===")
        for failure in failures {
            print(failure)
        }
        print("Passed: \(passed)  Failed: \(failed)")
        if failed > 0 {
            print("SOME TESTS FAILED")
        } else {
            print("ALL TESTS PASSED ✓")
        }
    }
}
