import XCTest
@testable import TwisterCore

final class CommandLineSignalTests:XCTestCase {
    func testSignalCancelsTheTokenAndReportsTheShellExitCode() throws {
        let token=CancellationToken(),signals=SignalCancellation(token:token,signals:[SIGUSR1])
        XCTAssertNil(signals.receivedSignal);XCTAssertEqual(signals.exitCode(1),1)
        kill(getpid(),SIGUSR1)
        let deadline=Date().addingTimeInterval(5)
        while !token.isCancelled && Date()<deadline { Thread.sleep(forTimeInterval:0.02) }
        XCTAssertTrue(token.isCancelled)
        XCTAssertEqual(signals.receivedSignal,SIGUSR1);XCTAssertEqual(signals.exitCode(1),128+SIGUSR1)
    }

    /// Runs the built command with a media probe that never finishes, then
    /// interrupts it the way Ctrl-C and `kill` do.
    func testInterruptedCommandStopsItsHelperAndRemovesStagedExports() throws {
        let cli=Bundle(for:Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("twister-cli")
        guard FileManager.default.isExecutableFile(atPath:cli.path) else { throw XCTSkip("twister-cli is not built.") }
        for (number,expected) in [(SIGINT,Int32(130)),(SIGTERM,Int32(143))] {
            let root=try OutputFiles.temporaryDirectory();defer{try? FileManager.default.removeItem(at:root)}
            let tools=root.appendingPathComponent("Tools",isDirectory:true),media=root.appendingPathComponent("Media",isDirectory:true)
            try FileManager.default.createDirectory(at:tools,withIntermediateDirectories:true)
            try FileManager.default.createDirectory(at:media,withIntermediateDirectories:true)
            let probe=tools.appendingPathComponent("hung-probe"),marker=tools.appendingPathComponent("started"),input=media.appendingPathComponent("clip.wav")
            try Data("#!/bin/sh\nsleep 120 &\necho $! > \"$TWISTER_TEST_MARKER\"\nwait\n".utf8).write(to:probe)
            try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:probe.path)
            try Data("RIFF".utf8).write(to:input)
            let process=Process()
            process.executableURL=cli;process.arguments=["convert","mp3",input.path]
            process.environment=ProcessInfo.processInfo.environment.merging(["TWISTER_FFPROBE":probe.path,"TWISTER_TEST_MARKER":marker.path]){_,new in new}
            process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
            try process.run()
            defer { if process.isRunning { kill(process.processIdentifier,SIGKILL) } }
            var deadline=Date().addingTimeInterval(20),helper:pid_t?
            while helper==nil && Date()<deadline {
                helper=(try? String(contentsOf:marker,encoding:.utf8)).flatMap{pid_t($0.trimmingCharacters(in:.whitespacesAndNewlines))}
                Thread.sleep(forTimeInterval:0.05)
            }
            let sleeper=try XCTUnwrap(helper,"The probe did not start.")
            defer { kill(sleeper,SIGKILL) }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:media.path).contains{$0.hasPrefix(".Twister-")})
            kill(process.processIdentifier,number)
            deadline=Date().addingTimeInterval(20)
            while process.isRunning && Date()<deadline { Thread.sleep(forTimeInterval:0.05) }
            XCTAssertFalse(process.isRunning)
            XCTAssertEqual(process.terminationReason,.exit);XCTAssertEqual(process.terminationStatus,expected)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:media.path),["clip.wav"])
            deadline=Date().addingTimeInterval(5)
            while kill(sleeper,0)==0 && Date()<deadline { Thread.sleep(forTimeInterval:0.05) }
            XCTAssertNotEqual(kill(sleeper,0),0,"The helper outlived the interrupted command.")
        }
    }
}
