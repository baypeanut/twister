import XCTest
@testable import TwisterCore

final class ProcessProtocolRestrictionTests: XCTestCase {
    private let restriction = ["-protocol_whitelist", ProcessRunner.localProtocols]
    private let local = ProcessRunner.localProtocols

    func testEveryFFmpegInputReceivesTheLocalProtocolRestriction() {
        let ffmpeg = URL(fileURLWithPath: "/opt/tools/ffmpeg")
        let arguments = ["-v", "error", "-i", "/a.mp4", "-f", "concat", "-i", "/list.txt", "-i", "/b.wav", "-map", "0:v", "/out.mp4"]
        let expected: [String] = ["-v", "error", "-protocol_whitelist", local, "-i", "/a.mp4", "-f", "concat", "-protocol_whitelist", local, "-i", "/list.txt",
                                  "-protocol_whitelist", local, "-i", "/b.wav", "-map", "0:v", "/out.mp4"]
        XCTAssertEqual(ProcessRunner.localOnlyArguments(ffmpeg, arguments, environment: [:]), expected)
    }

    func testAnExplicitRestrictionIsKeptForItsOwnInputOnly() {
        let ffmpeg = URL(fileURLWithPath: "/opt/tools/ffmpeg")
        let expected: [String] = ["-protocol_whitelist", "file", "-i", "/a.mp4", "-protocol_whitelist", local, "-i", "/b.mp4", "/out.mp4"]
        XCTAssertEqual(ProcessRunner.localOnlyArguments(ffmpeg, ["-protocol_whitelist", "file", "-i", "/a.mp4", "-i", "/b.mp4", "/out.mp4"], environment: [:]), expected)
    }

    func testOverridePathsWithOtherFileNamesAreRestricted() {
        let environment = ["TWISTER_FFMPEG": "/opt/media/ffmpeg-7.1", "TWISTER_FFPROBE": "/opt/media/probe"]
        let inputs: [String] = ["-protocol_whitelist", local, "-i", "/a.mp4", "-protocol_whitelist", local, "-i", "/b.mp4", "/out.mp4"]
        XCTAssertEqual(ProcessRunner.localOnlyArguments(URL(fileURLWithPath: "/opt/media/ffmpeg-7.1"), ["-i", "/a.mp4", "-i", "/b.mp4", "/out.mp4"], environment: environment), inputs)
        let probe: [String] = ["-protocol_whitelist", local, "-v", "error", "/a.mp4"]
        XCTAssertEqual(ProcessRunner.localOnlyArguments(URL(fileURLWithPath: "/opt/media/probe"), ["-v", "error", "/a.mp4"], environment: environment), probe)
    }

    func testProbesAndOtherToolsKeepTheirArguments() {
        XCTAssertEqual(ProcessRunner.localOnlyArguments(URL(fileURLWithPath: "/usr/local/bin/ffprobe"), ["-of", "json", "/a.mp4"], environment: [:]), restriction + ["-of", "json", "/a.mp4"])
        XCTAssertEqual(ProcessRunner.localOnlyArguments(URL(fileURLWithPath: "/usr/bin/zip"), ["-i", "/a.mp4"], environment: ["TWISTER_FFMPEG": "/opt/media/ffmpeg-7.1"]), ["-i", "/a.mp4"])
    }

    func testSecondInputIsOpenedWithTheSameRestrictionAsTheFirst() throws {
        guard let ffmpeg = try? Dependencies.executable("ffmpeg") else { throw XCTSkip("FFmpeg is not installed.") }
        let root = try OutputFiles.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let tone = root.appendingPathComponent("tone.wav"), playlist = root.appendingPathComponent("remote.m3u8")
        try ProcessRunner.run(ffmpeg, ["-v", "error", "-nostdin", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.2", tone.path])
        // The segment is never requested. FFmpeg names the list that refused it,
        // which is its own narrower default when an input was left uncovered.
        try Data("#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:1,\nhttp://127.0.0.1:9/segment.ts\n#EXT-X-ENDLIST\n".utf8).write(to: playlist)
        XCTAssertThrowsError(try ProcessRunner.run(ffmpeg, ["-v", "error", "-nostdin", "-i", tone.path, "-i", playlist.path, "-f", "null", "-"])) { error in
            XCTAssertTrue(error.localizedDescription.contains("not on whitelist '\(ProcessRunner.localProtocols)'"), error.localizedDescription)
        }
    }
}
