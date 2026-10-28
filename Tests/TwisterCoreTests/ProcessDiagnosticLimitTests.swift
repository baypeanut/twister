import XCTest
@testable import TwisterCore

final class ProcessDiagnosticLimitTests: XCTestCase {
    func testLargeDiagnosticsAreDrainedAndKeepTheirUsefulTail() throws {
        let result = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/perl"),
            ["-e", "print STDERR 'x' x 3000000; print STDERR 'final diagnostic'; print 'complete'"])
        XCTAssertEqual(result.text, "complete")
        XCTAssertEqual(result.errorOutput.count, ProcessRunner.diagnosticByteLimit)
        XCTAssertTrue(String(decoding: result.errorOutput, as: UTF8.self).hasSuffix("final diagnostic"))
    }

    func testFailureRetainsFinalErrorAfterLargeDiagnostics() {
        XCTAssertThrowsError(try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/perl"),
            ["-e", "print STDERR 'x' x 3000000; print STDERR 'specific failure'; exit 7"])) { error in
            XCTAssertTrue(error.localizedDescription.hasSuffix("specific failure"))
            XCTAssertLessThanOrEqual(error.localizedDescription.utf8.count, 6000)
        }
    }
}
