import XCTest
@testable import TwisterCore

final class ProcessFailureReasonTests: XCTestCase {
    func testCapturedFFmpegFailurePrefersThePNGSignature() {
        let diagnostics = """
        [png @ 0x7773048380] Invalid PNG signature 0x6E6F74206120706E.
        [in#0/image2 @ 0x777301c000] Could not find codec parameters for stream 0 (Video: png, none): unspecified size
        Consider increasing the value for the 'analyzeduration' (0) and 'probesize' (5000000) options
        Input #0, image2, from '/tmp/fixture/corrupt.png':
          Duration: 00:00:00.04, start: 0.000000, bitrate: 2 kb/s
          Stream #0:0: Video: png, none, 25 fps, 25 tbr, 25 tbn
        Stream mapping:
          Stream #0:0 -> #0:0 (png (native) -> mjpeg (native))
        Press [q] to stop, [?] for help
        [png @ 0x7773049180] Invalid PNG signature 0x6E6F74206120706E.
        [vist#0:0/png @ 0x7773014300] [dec:png @ 0x7772c0c280] Decoding error: Invalid data found when processing input
        [vist#0:0/png @ 0x7773014300] [dec:png @ 0x7772c0c280] Decode error rate 1 exceeds maximum 0.666667
        [vf#0:0 @ 0x7772c54000] Cannot determine format of input 0:0 after EOF
        [vf#0:0 @ 0x7772c54000] Task finished with error code: -1094995529 (Invalid data found when processing input)
        [vf#0:0 @ 0x7772c54000] Terminating thread with return code -1094995529 (Invalid data found when processing input)
        [vost#0:0/mjpeg @ 0x7773054000] [enc:mjpeg @ 0x7772c015e0] Could not open encoder before EOF
        [vost#0:0/mjpeg @ 0x7773054000] Task finished with error code: -22 (Invalid argument)
        [vost#0:0/mjpeg @ 0x7773054000] Terminating thread with return code -22 (Invalid argument)
        [vist#0:0/png @ 0x7773014300] [dec:png @ 0x7772c0c280] Task finished with error code: -1145393733 (Error number -1145393733 occurred)
        [vist#0:0/png @ 0x7773014300] [dec:png @ 0x7772c0c280] Terminating thread with return code -1145393733 (Error number -1145393733 occurred)
        [out#0/image2 @ 0x777300c840] Nothing was written into output file, because at least one of its streams received no packets.
        frame=    0 fps=0.0 q=0.0 Lsize=       0KiB time=N/A bitrate=N/A speed=N/A elapsed=0:00:00.00
        Conversion failed!
        """
        XCTAssertEqual(ProcessRunner.failureReason(from: diagnostics, tool: "ffmpeg", code: 69),
                       "Invalid PNG signature 0x6E6F74206120706E.")
    }

    func testCapturedOfficeFailureOmitsFontWarnings() {
        let diagnostics = """
        Fontconfig warning: no <cachedir> elements found. Check configuration.
        Fontconfig warning: adding <cachedir>/usr/local/var/cache/fontconfig</cachedir>
        Fontconfig warning: adding <cachedir prefix="xdg">fontconfig</cachedir>
        Fontconfig warning: no <cachedir> elements found. Check configuration.
        Fontconfig warning: adding <cachedir>/usr/local/var/cache/fontconfig</cachedir>
        Fontconfig warning: adding <cachedir prefix="xdg">fontconfig</cachedir>
        Error: source file could not be loaded
        """
        XCTAssertEqual(ProcessRunner.failureReason(from: diagnostics, tool: "soffice", code: 1),
                       "Error: source file could not be loaded")
    }

    func testCapturedExifToolFailureKeepsTheCause() {
        XCTAssertEqual(ProcessRunner.failureReason(from: "Error: File not found - /tmp/fixture/absent.jpg", tool: "exiftool", code: 1),
                       "Error: File not found - /tmp/fixture/absent.jpg")
    }

    func testNestedPrefixesAndThreadNoiseAreRemoved() {
        let diagnostics = """
        [vf#0:0 @ 0x123] Task finished with error code: -22 (Invalid argument)
        [vist#0:0/png @ 0x123] [dec:png @ 0x456] Invalid data found when processing input
        [vf#0:0 @ 0x123] Terminating thread with return code -22
        """
        XCTAssertEqual(ProcessRunner.failureReason(from: diagnostics, tool: "ffmpeg", code: 1),
                       "Invalid data found when processing input")
    }

    func testEmptyAndMegabyteNoiseUseExistingExitMessage() {
        for diagnostics in ["", "  \n ", String(repeating: "[vf @ 0x123] Terminating thread with return code -22\n", count: 22_000)] {
            XCTAssertEqual(ProcessRunner.failureReason(from: diagnostics, tool: "ffmpeg", code: 7),
                           "ffmpeg exited with code 7.")
        }
    }

    func testReasonsAreBoundedAndKeepAnUnknownToolsTail() {
        let diagnostic = String(repeating: "x", count: 1_000_000) + "specific failure"
        let reason = ProcessRunner.failureReason(from: diagnostic, tool: "helper", code: 7)
        XCTAssertLessThanOrEqual(reason.count, 300)
        XCTAssertTrue(reason.hasSuffix("specific failure"))
        XCTAssertFalse(reason.contains("\n"))
        let lateCause = ProcessRunner.failureReason(from: String(repeating: "x", count: 1_000_000) + "Permission denied", tool: "helper", code: 1)
        XCTAssertTrue(lateCause.hasSuffix("Permission denied"))
        XCTAssertLessThanOrEqual(lateCause.count, 300)
        let longCause = ProcessRunner.failureReason(from: "Permission denied: " + String(repeating: "é", count: 1000), tool: "helper", code: 1)
        XCTAssertTrue(longCause.hasPrefix("Permission denied:"))
        XCTAssertEqual(longCause.count, 300)
    }

    func testEncoderInitializationKeepsTheExistingRecoveryContract() {
        let reason = ProcessRunner.failureReason(from: "[libvorbis @ 0x123] encoder setup failed\n[af @ 0x456] Task finished with error code: -22", tool: "ffmpeg", code: 234)
        XCTAssertEqual(reason, "libvorbis: encoder setup failed")
        let nested = ProcessRunner.failureReason(from: "[aost @ 0x123] [enc:libvorbis @ 0x456] encoder setup failed", tool: "ffmpeg", code: 234)
        XCTAssertEqual(nested, "enc:libvorbis: encoder setup failed")
    }

    func testFailureKeepsFullBoundedDiagnosticsForCallers() {
        let diagnostics = "[png @ 0x123] Invalid PNG signature.\n[vf @ 0x456] Terminating thread\n"
        var captured = Data()
        XCTAssertThrowsError(try ProcessRunner.run(URL(fileURLWithPath: "/bin/sh"),
            ["-c", "printf '%s' \"$1\" >&2; exit 7", "fixture", diagnostics], onDiagnostics: { captured = $0 })) { error in
            guard case TwisterError.failed(let reason) = error else { return XCTFail("Expected the existing failure type") }
            XCTAssertEqual(reason, "Invalid PNG signature.")
        }
        XCTAssertEqual(captured, Data(diagnostics.utf8))
    }
}
