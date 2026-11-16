import XCTest
import CryptoKit
@testable import TwisterCore

final class ToolGroupTests:XCTestCase {
    func testMediaInstallationAloneResolvesTheMediaTools() throws {
        try temporary { root in
            let store=ToolStore(root:root)
            try tool(root,"media-v1/ffmpeg");try tool(root,"media-v1/ffprobe")
            let status=ToolSetupStatus { store.executable($0) }
            XCTAssertTrue(status.mediaReady);XCTAssertFalse(status.webReady);XCTAssertFalse(status.officeReady)
            XCTAssertEqual(status.missing,[.office])
            XCTAssertNil(store.executable("yt-dlp"));XCTAssertNil(store.executable("deno"))
            XCTAssertEqual(store.installedItems(.web),[])
        }
    }
    func testMediaEnginesAskOnlyForFFmpegAndFFprobe() throws {
        let sources=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/TwisterCore")
        let call=try NSRegularExpression(pattern:#"Dependencies\.executable\("([^"]+)"\)"#)
        for file in ["MediaEngine.swift","MediaPreviewEngine.swift","ImageEngine.swift","ConversionEngine.swift"] {
            let text=try String(contentsOf:sources.appendingPathComponent(file),encoding:.utf8)
            let names=Set(call.matches(in:text,range:NSRange(text.startIndex...,in:text)).compactMap { Range($0.range(at:1),in:text).map { String(text[$0]) } })
            XCTAssertTrue(names.isSubset(of:["ffmpeg","ffprobe"]),"\(file): \(names)")
            for web in ToolGroup.web.tools { XCTAssertFalse(text.contains("\""+web+"\""),"\(file) refers to \(web)") }
        }
    }
    func testWebToolsResolveFromTheirOwnDirectoryAndFromAnEarlierSetup() throws {
        try temporary { root in
            let store=ToolStore(root:root)
            try tool(root,"media-v1/ffmpeg");try tool(root,"media-v1/ffprobe");try tool(root,"media-v1/yt-dlp");try tool(root,"media-v1/deno")
            XCTAssertEqual(store.executable("yt-dlp"),root.appendingPathComponent("media-v1/yt-dlp"))
            XCTAssertTrue(ToolSetupStatus { store.executable($0) }.webReady)
            try tool(root,"web-v1/yt-dlp");try tool(root,"web-v1/deno")
            XCTAssertEqual(store.executable("deno"),root.appendingPathComponent("web-v1/deno"))
        }
    }
    func testRemovingWebKeepsMediaAndOffice() throws {
        try temporary { root in
            let store=ToolStore(root:root)
            for path in ["media-v1/ffmpeg","media-v1/ffprobe","media-v1/yt-dlp","media-v1/deno","web-v1/yt-dlp","web-v1/deno","office-26.8.1/LibreOffice.app/Contents/MacOS/soffice"] { try tool(root,path) }
            try Data("mine".utf8).write(to:root.appendingPathComponent("notes.txt"))
            let plan=try store.remove(.web)
            XCTAssertEqual(Set(plan.remove.map(\.lastPathComponent)),["web-v1","yt-dlp","deno"]);XCTAssertEqual(plan.kept,[])
            let status=ToolSetupStatus { store.executable($0) }
            XCTAssertEqual([status.mediaReady,status.webReady,status.officeReady],[true,false,true])
            XCTAssertFalse(exists(root,"web-v1"));XCTAssertTrue(exists(root,"notes.txt"))
            XCTAssertEqual(store.removalPlan(.web).remove,[])
            try store.remove(.media)
            XCTAssertFalse(exists(root,"media-v1"));XCTAssertTrue(exists(root,"office-26.8.1/LibreOffice.app/Contents/MacOS/soffice"))
            try store.remove(.office)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path),["notes.txt"])
        }
    }
    func testRemovingMediaKeepsWebToolsOfAnEarlierSetup() throws {
        try temporary { root in
            let store=ToolStore(root:root)
            for path in ["media-v1/ffmpeg","media-v1/ffprobe","media-v1/yt-dlp","media-v1/deno"] { try tool(root,path) }
            try store.remove(.media)
            XCTAssertNil(store.executable("ffmpeg"));XCTAssertNotNil(store.executable("yt-dlp"));XCTAssertNotNil(store.executable("deno"))
        }
    }
    func testRemovalNeverLeavesTheToolDirectory() throws {
        try temporary { base in
            let root=base.appendingPathComponent("Tools"),outside=base.appendingPathComponent("homebrew")
            try tool(outside,"yt-dlp");try tool(outside,"deno");try tool(outside,"ffmpeg");try tool(outside,"bin/tool")
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            // A link in place of the shared directory must not lead the removal outside.
            try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("media-v1"),withDestinationURL:outside)
            // A link in place of the group's own directory is unlinked, not followed.
            try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("web-v1"),withDestinationURL:outside.appendingPathComponent("bin"))
            let store=ToolStore(root:root)
            XCTAssertFalse(store.owns(root.appendingPathComponent("media-v1/yt-dlp")))
            XCTAssertFalse(store.owns(root.appendingPathComponent("../homebrew/yt-dlp")))
            XCTAssertFalse(store.owns(root.appendingPathComponent("web-v1/..")))
            let plan=try store.remove(.web)
            XCTAssertEqual(plan.remove.map(\.lastPathComponent),["web-v1"])
            XCTAssertFalse(exists(root,"web-v1"))
            for path in ["yt-dlp","deno","bin/tool"] { XCTAssertTrue(exists(outside,path),path) }
            try store.remove(.media)
            XCTAssertTrue(exists(outside,"yt-dlp"));XCTAssertTrue(exists(outside,"ffmpeg"));XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath:root.appendingPathComponent("media-v1").path))
        }
    }
    func testOverrideTargetsAreNotRemoved() throws {
        try temporary { root in
            let store=ToolStore(root:root)
            try tool(root,"web-v1/yt-dlp");try tool(root,"web-v1/deno");try tool(root,"media-v1/yt-dlp");try tool(root,"media-v1/ffmpeg")
            let environment=["TWISTER_DENO":root.appendingPathComponent("web-v1/deno").path,"TWISTER_FFMPEG":"/opt/homebrew/bin/ffmpeg"]
            let protected=ToolStore.overrides(.web,environment:environment)
            XCTAssertEqual(protected.map(\.path),[root.appendingPathComponent("web-v1/deno").path])
            let plan=try store.remove(.web,protected:protected)
            XCTAssertEqual(plan.kept.map(\.lastPathComponent),["web-v1"]);XCTAssertEqual(plan.remove.map(\.lastPathComponent),["yt-dlp"])
            XCTAssertTrue(exists(root,"web-v1/deno"));XCTAssertTrue(exists(root,"web-v1/yt-dlp"));XCTAssertFalse(exists(root,"media-v1/yt-dlp"))
            XCTAssertTrue(exists(root,"media-v1/ffmpeg"))
        }
    }
    func testReportNamesTheSourceAndWhatCanBeRemoved() throws {
        try temporary { base in
            let root=base.appendingPathComponent("Tools"),bundle=base.appendingPathComponent("Twister.app/Contents/Resources"),brew=base.appendingPathComponent("brew")
            let store=ToolStore(root:root)
            try tool(root,"web-v1/yt-dlp");try tool(root,"web-v1/deno");try tool(bundle,"Tools/ffmpeg");try tool(brew,"ffprobe");try tool(brew,"soffice")
            let found=["yt-dlp":root.appendingPathComponent("web-v1/yt-dlp"),"deno":root.appendingPathComponent("web-v1/deno"),
                       "ffmpeg":bundle.appendingPathComponent("Tools/ffmpeg"),"ffprobe":brew.appendingPathComponent("ffprobe"),"soffice":brew.appendingPathComponent("soffice")]
            let environment=["TWISTER_SOFFICE":brew.appendingPathComponent("soffice").path]
            let web=store.report(.web,environment:environment,bundle:bundle) { found[$0] }
            XCTAssertTrue(web.ready);XCTAssertEqual(web.source,.installed);XCTAssertTrue(web.removable);XCTAssertEqual(web.version,"yt-dlp 2026.08.19 · Deno 2.9.7")
            let media=store.report(.media,environment:environment,bundle:bundle) { found[$0] }
            XCTAssertEqual(media.tools.map(\.source),[.bundled,.system]);XCTAssertNil(media.source);XCTAssertNil(media.version);XCTAssertFalse(media.removable)
            let office=store.report(.office,environment:environment,bundle:bundle) { found[$0] }
            XCTAssertEqual(office.source,.override);XCTAssertFalse(office.removable)
            let missing=store.report(.web,environment:[:],bundle:bundle) { _ in nil }
            XCTAssertFalse(missing.ready);XCTAssertNil(missing.source);XCTAssertTrue(missing.removable)
            XCTAssertGreaterThan(store.size(.web),0);XCTAssertEqual(store.size(.office),0)
        }
    }
    func testArchiveIsCheckedBeforeItIsOpened() throws {
        try temporary { root in
            let source=root.appendingPathComponent("source");try tool(source,"ffmpeg")
            let archive=root.appendingPathComponent("ffmpeg.zip")
            try ProcessRunner.run(URL(fileURLWithPath:"/usr/bin/zip"),["-j","-q",archive.path,source.appendingPathComponent("ffmpeg").path])
            let archiveDigest=try digest(archive),memberDigest=try digest(source.appendingPathComponent("ffmpeg")),wrong=String(repeating:"0",count:64)
            func attempt(_ download:String,_ member:String?) throws -> (placed:URL,unpack:URL) {
                let stage=root.appendingPathComponent(UUID().uuidString),copy=stage.appendingPathComponent("download-0"),unpack=stage.appendingPathComponent("unpack-0")
                try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:false);try FileManager.default.copyItem(at:archive,to:copy)
                let package=ExternalToolSetup.Package(name:"ffmpeg",url:"https://example.invalid/ffmpeg.zip",download:download,member:member)
                defer { rejectedUnpack=FileManager.default.fileExists(atPath:unpack.path) }
                try ExternalToolSetup.place(package,download:copy,in:stage,unpack:unpack,token:.init())
                return (stage.appendingPathComponent("ffmpeg"),unpack)
            }
            var rejectedUnpack=false
            XCTAssertThrowsError(try attempt(wrong,memberDigest));XCTAssertFalse(rejectedUnpack,"A rejected archive was extracted")
            // The checksum of the executable alone no longer admits its archive.
            XCTAssertThrowsError(try attempt(memberDigest,memberDigest));XCTAssertFalse(rejectedUnpack,"A rejected archive was extracted")
            XCTAssertThrowsError(try attempt(archiveDigest,wrong))
            let placed=try attempt(archiveDigest,memberDigest).placed
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath:placed.path));XCTAssertEqual(try digest(placed),memberDigest)
        }
    }
    func testEveryPinnedArchiveHasADownloadAndAMemberChecksum() {
        let hex=CharacterSet(charactersIn:"0123456789abcdef")
        for package in ExternalToolSetup.mediaPackages+ExternalToolSetup.webPackages {
            XCTAssertTrue(package.url.hasPrefix("https://"),package.name)
            XCTAssertTrue(package.download.count==64 && package.download.unicodeScalars.allSatisfy(hex.contains),package.name)
            if package.url.hasSuffix(".zip") {
                XCTAssertTrue(package.member?.count==64 && package.member?.unicodeScalars.allSatisfy(hex.contains)==true,package.name)
                XCTAssertNotEqual(package.member,package.download,package.name)
            } else { XCTAssertNil(package.member,package.name) }
        }
        XCTAssertEqual(ExternalToolSetup.mediaPackages.map(\.name),ToolGroup.media.tools)
        XCTAssertEqual(ExternalToolSetup.webPackages.map(\.name),ToolGroup.web.tools)
    }
    private func digest(_ file:URL) throws -> String { SHA256.hash(data:try Data(contentsOf:file)).map { String(format:"%02x",$0) }.joined() }
    private func exists(_ root:URL,_ path:String)->Bool { FileManager.default.fileExists(atPath:root.appendingPathComponent(path).path) }
    private func tool(_ root:URL,_ path:String) throws {
        let file=root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to:file);try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:file.path)
    }
    private func temporary(_ run:(URL)throws->Void)throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:root) };try run(root)
    }
}
