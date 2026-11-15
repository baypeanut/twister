import XCTest
@testable import TwisterCore

final class ProcessRunnerTimeoutTests: XCTestCase {
    private let shell = URL(fileURLWithPath: "/bin/sh")
    private final class Output: @unchecked Sendable {
        private let lock = NSLock(); private var data = Data()
        func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
        var pid: pid_t? { lock.lock(); defer { lock.unlock() }; return pid_t(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    private func waitForExit(_ pid: pid_t) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline { if kill(pid, 0) != 0 { return true }; Thread.sleep(forTimeInterval: 0.05) }
        return false
    }

    func testTimeoutStopsAHungProcessAndTheHelperItStarted() throws {
        let output = Output(), started = Date()
        XCTAssertThrowsError(try ProcessRunner.run(shell, ["-c", "sleep 60 & echo $!; wait"], timeout: 0.5, onOutput: { output.append($0) })) { error in
            XCTAssertTrue(error.localizedDescription.contains("took too long"), error.localizedDescription)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertTrue(waitForExit(try XCTUnwrap(output.pid)))
    }

    func testHelperHoldingThePipesCannotBlockAfterItsParentExits() throws {
        let started = Date()
        let result = try ProcessRunner.run(shell, ["-c", "sleep 60 >&2 & echo $!"])
        XCTAssertLessThan(Date().timeIntervalSince(started), 15)
        let pid = try XCTUnwrap(pid_t(result.text.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertTrue(waitForExit(pid))
    }

    func testCancellationStopsTheWholeProcessGroup() throws {
        let token = CancellationToken(), output = Output(), started = Date()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { token.cancel() }
        XCTAssertThrowsError(try ProcessRunner.run(shell, ["-c", "sleep 60 & echo $!; wait"], token: token, onOutput: { output.append($0) })) { error in
            guard case TwisterError.cancelled = error else { return XCTFail("Expected cancellation, got \(error)") }
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertTrue(waitForExit(try XCTUnwrap(output.pid)))
    }

    func testWorkFinishingInsideItsTimeoutKeepsDirectoryEnvironmentAndExitCode() throws {
        let directory = try OutputFiles.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        try Data("here\n".utf8).write(to: directory.appendingPathComponent("relative.txt"))
        let result = try ProcessRunner.run(shell, ["-c", "cat relative.txt; echo $TWISTER_TEST_VALUE"], directory: directory, environment: ["TWISTER_TEST_VALUE": "kept"], timeout: 30)
        XCTAssertEqual(result.text, "here\nkept\n")
        XCTAssertThrowsError(try ProcessRunner.run(shell, ["-c", "exit 7"], timeout: 30)) { error in
            XCTAssertEqual(error.localizedDescription, "sh exited with code 7.")
        }
        XCTAssertThrowsError(try ProcessRunner.run(directory.appendingPathComponent("missing"), []))
    }
}
