import Foundation
import CryptoKit

/// Public packages keep large upstream runtimes outside the signed app bundle.
/// Setup acquires exact upstream versions, verifies hashes, stages them and only
/// then publishes a complete tool directory. No credential store is involved.
public enum ExternalToolSetup {
    public static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Twister/Tools", isDirectory:true)
    }
    public static var store:ToolStore { ToolStore(root:root) }
    public static func executable(_ name:String)->URL? { store.executable(name) }
    private static func usable(_ url:URL)->Bool { ToolStore.usable(url) }
    public static var status:ToolSetupStatus { ToolSetupStatus { try? Dependencies.executable($0) } }
    public static var mediaReady:Bool { status.mediaReady }
    public static var webReady:Bool { status.webReady }
    public static var officeReady:Bool { status.officeReady }
    /// Where each tool of a group resolves from and whether setup can remove it.
    public static func report(_ group:ToolGroup)->ToolGroupReport {
        store.report(group,environment:ProcessInfo.processInfo.environment,bundle:Bundle.main.resourceURL) { try? Dependencies.executable($0) }
    }
    public static func installedSize(_ group:ToolGroup)->Int64 { store.size(group) }
    /// Deletes the files setup installed for one group. Tools from Homebrew,
    /// the application bundle or a `TWISTER_` override stay where they are.
    public static func remove(_ group:ToolGroup) throws {
        try store.remove(group,protected:ToolStore.overrides(group,environment:ProcessInfo.processInfo.environment))
    }
    public static func install(_ group:ToolGroup,token:CancellationToken,progress:@escaping @Sendable (Double?,String)->Void) async throws {
        switch group {
        case .media:try await installMedia(token:token,progress:progress)
        case .web:try await installWeb(token:token,progress:progress)
        case .office:try await installOffice(token:token,progress:progress)
        }
    }
    /// A pinned upstream download. An archive is checked before it is opened,
    /// and the executable taken from it is checked again.
    struct Package:Sendable {
        let name:String,url:String
        /// SHA-256 of the downloaded file.
        let download:String
        /// SHA-256 of the executable inside an archive; nil for a plain binary.
        let member:String?
    }
    static let mediaPackages=[
        Package(name:"ffmpeg",url:"https://www.osxexperts.net/ffmpeg9arm.zip",download:"d0c06c5c68ce48af3143b262f7a9118a7c9f67de1e237fcc24ffb14df9c67af9",member:"591260c945d0eef150e3bf82b0ef988bd36a9cecc18ff05d6679617159f0a95e"),
        Package(name:"ffprobe",url:"https://www.osxexperts.net/ffprobe9arm.zip",download:"0c94fbdd8917022f28115eca512196cf4648732bc9e5db9ec8896c7e519d02aa",member:"e11c17e8200b3ee4c4c186d245e2b4053f01d56957336c1817fca0b997469106")
    ]
    static let webPackages=[
        Package(name:"yt-dlp",url:"https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp_macos",download:"0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202",member:nil),
        Package(name:"deno",url:"https://github.com/denoland/deno/releases/download/v2.9.7/deno-aarch64-apple-darwin.zip",download:"5cd46d6268f6f78f5d88bdc7159d20bd44cdaa4b3303474839f87ec6fe7ae25c",member:"b73737579d5a84c160e3316487594783fa5c15f4e13252a6a07050b755317f1a")
    ]
    public static func installMedia(token:CancellationToken,progress:@escaping @Sendable (Double?,String)->Void) async throws {
        try token.check();try Task.checkCancellation()
        if mediaReady { progress(1,"Media tools are ready.");return }
        let target=root.appendingPathComponent(ToolStore.mediaDirectory,isDirectory:true)
        try await install(mediaPackages,stagePrefix:".media-",target:target,token:token,progress:progress) { stage in
            // An earlier setup kept the web tools in this directory; a repair keeps them.
            for name in ToolGroup.web.tools where usable(target.appendingPathComponent(name)) {
                try FileManager.default.copyItem(at:target.appendingPathComponent(name),to:stage.appendingPathComponent(name))
            }
        }
        progress(1,"Media tools are ready.")
    }
    public static func installWeb(token:CancellationToken,progress:@escaping @Sendable (Double?,String)->Void) async throws {
        try token.check();try Task.checkCancellation()
        if webReady { progress(1,"Web download tools are ready.");return }
        try await install(webPackages,stagePrefix:".web-",target:root.appendingPathComponent(ToolStore.webDirectory,isDirectory:true),token:token,progress:progress)
        progress(1,"Web download tools are ready.")
    }
    private static func install(_ packages:[Package],stagePrefix:String,target:URL,token:CancellationToken,progress:@escaping @Sendable (Double?,String)->Void,
                                carryOver:(URL) throws->Void={_ in}) async throws {
        let fm=FileManager.default;try fm.createDirectory(at:root,withIntermediateDirectories:true)
        let stage=root.appendingPathComponent(stagePrefix+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:stage,withIntermediateDirectories:false)
        defer { try? fm.removeItem(at:stage) }
        for (index,package) in packages.enumerated() {
            try token.check();try Task.checkCancellation()
            let archive=stage.appendingPathComponent("download-\(index)")
            try await CheckedToolDownload.fetch(URL(string:package.url)!,to:archive,maximum:400*1024*1024) { fraction in
                progress(fraction.map{(Double(index)+$0)/Double(packages.count)},"Downloading \(package.name)…")
            }
            try place(package,download:archive,in:stage,unpack:stage.appendingPathComponent("unpack-\(index)",isDirectory:true),token:token)
        }
        try token.check();try Task.checkCancellation()
        try carryOver(stage)
        let names=packages.map(\.name)
        try ToolInstallation.publish(stage,to:target) { directory in names.allSatisfy { usable(directory.appendingPathComponent($0)) } }
    }
    /// Nothing is extracted from a download whose checksum differs.
    static func place(_ package:Package,download:URL,in stage:URL,unpack:URL,token:CancellationToken) throws {
        let fm=FileManager.default
        try verify(download,digest:package.download)
        let output=stage.appendingPathComponent(package.name)
        if let member=package.member {
            try ArchiveCodec.extract(download,into:unpack,token:token)
            let candidate=unpack.appendingPathComponent(package.name)
            let values=try candidate.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            guard values.isRegularFile == true,values.isSymbolicLink != true else { throw TwisterError.failed("Upstream package has no regular \(package.name) executable.") }
            try verify(candidate,digest:member)
            try fm.moveItem(at:candidate,to:output);try fm.removeItem(at:unpack)
        } else { try fm.moveItem(at:download,to:output) }
        try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:output.path)
        if fm.fileExists(atPath:download.path) { try fm.removeItem(at:download) }
    }
    public static func installOffice(token:CancellationToken,progress:@escaping @Sendable (Double?,String)->Void) async throws {
        try token.check();try Task.checkCancellation()
        if officeReady { progress(1,"Office tools are ready.");return }
        let fm=FileManager.default;try fm.createDirectory(at:root,withIntermediateDirectories:true)
        let stage=root.appendingPathComponent(".office-\(UUID().uuidString)",isDirectory:true)
        try fm.createDirectory(at:stage,withIntermediateDirectories:false);defer { try? fm.removeItem(at:stage) }
        let image=stage.appendingPathComponent("LibreOffice.dmg")
        try await CheckedToolDownload.fetch(URL(string:"https://download.documentfoundation.org/libreoffice/stable/26.8.1/mac/aarch64/LibreOffice_26.8.1_MacOS_aarch64.dmg")!,to:image,maximum:400*1024*1024) { progress($0.map{$0*0.8},"Downloading LibreOffice 26.8.1…") }
        try verify(image,digest:"ca074e0b13571efb30a31fc531c5f95e997030637325e5d5de92d67aefdf0dfc")
        try token.check();try Task.checkCancellation();progress(nil,"Verifying and preparing office tools…")
        let mount=stage.appendingPathComponent("mount",isDirectory:true);try fm.createDirectory(at:mount,withIntermediateDirectories:false)
        try ProcessRunner.run(URL(fileURLWithPath:"/usr/bin/hdiutil"),["attach","-nobrowse","-readonly","-mountpoint",mount.path,image.path],token:token)
        defer { _ = try? ProcessRunner.run(URL(fileURLWithPath:"/usr/bin/hdiutil"),["detach",mount.path]) }
        let content=stage.appendingPathComponent("content",isDirectory:true);try fm.createDirectory(at:content,withIntermediateDirectories:false)
        try ProcessRunner.run(URL(fileURLWithPath:"/usr/bin/ditto"),[mount.appendingPathComponent("LibreOffice.app").path,content.appendingPathComponent("LibreOffice.app").path],token:token)
        try token.check();try Task.checkCancellation()
        let target=root.appendingPathComponent(ToolStore.officeDirectory,isDirectory:true)
        try ToolInstallation.publish(content,to:target) { usable($0.appendingPathComponent("LibreOffice.app/Contents/MacOS/soffice")) }
        progress(1,"Office tools are ready.")
    }
    static func verify(_ file:URL,digest:String) throws {
        let input=try FileHandle(forReadingFrom:file);defer{try? input.close()};var hasher=SHA256()
        while let bytes=try input.read(upToCount:1024*1024),!bytes.isEmpty {hasher.update(data:bytes)}
        let actual=hasher.finalize().map{String(format:"%02x",$0)}.joined()
        guard actual == digest else {throw TwisterError.failed("The upstream download checksum did not match. Nothing was installed.")}
    }
}

private final class CheckedToolDownload:NSObject,URLSessionDownloadDelegate,@unchecked Sendable {
    private let target:URL;private let maximum:Int64;private let progress:@Sendable (Double?)->Void
    private var continuation:CheckedContinuation<Void,Error>?;private var failure:Error?
    private init(target:URL,maximum:Int64,progress:@escaping @Sendable (Double?)->Void) { self.target=target;self.maximum=maximum;self.progress=progress }
    static func fetch(_ url:URL,to target:URL,maximum:Int64,progress:@escaping @Sendable (Double?)->Void) async throws {
        let delegate=CheckedToolDownload(target:target,maximum:maximum,progress:progress)
        let session=URLSession(configuration:.ephemeral,delegate:delegate,delegateQueue:nil)
        let task=session.downloadTask(with:url)
        defer{session.finishTasksAndInvalidate()}
        try await withTaskCancellationHandler(operation:{
            try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
                delegate.continuation=continuation
                if Task.isCancelled {continuation.resume(throwing:CancellationError());delegate.continuation=nil;return}
                task.resume()
            }
        },onCancel:{task.cancel()})
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) { completionHandler(request.url?.scheme == "https" ? request:nil) }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) {
        if totalBytesWritten>maximum || totalBytesExpectedToWrite>maximum {failure=TwisterError.failed("The upstream download exceeds its size limit.");downloadTask.cancel();return}
        progress(totalBytesExpectedToWrite>0 ? Double(totalBytesWritten)/Double(totalBytesExpectedToWrite):nil)
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL) {
        do {
            guard let response=downloadTask.response as? HTTPURLResponse,(200...299).contains(response.statusCode),response.url?.scheme == "https" else {throw TwisterError.failed("The upstream server did not return a successful HTTPS download.")}
            let size=try location.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size>0,size<=maximum else {throw TwisterError.failed("The upstream download has an invalid size.")}
            try FileManager.default.moveItem(at:location,to:target)
        }catch{failure=error}
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
        guard let continuation else{return};self.continuation=nil
        if let failure=failure ?? error {continuation.resume(throwing:failure)}else{continuation.resume()}
    }
}
