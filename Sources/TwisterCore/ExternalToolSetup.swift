import Foundation
import CryptoKit
import Security

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
    public static var status:ToolSetupStatus { ToolSetupStatus { try? Dependencies.locate($0) } }
    public static var mediaReady:Bool { status.mediaReady }
    public static var webReady:Bool { status.webReady }
    public static var officeReady:Bool { status.officeReady }
    /// Where each tool of a group resolves from and whether setup can remove it.
    public static func report(_ group:ToolGroup)->ToolGroupReport {
        store.report(group,environment:overrideEnvironment,bundle:Bundle.main.resourceURL) { try? Dependencies.locate($0) }
    }
    public static func installedSize(_ group:ToolGroup)->Int64 { store.size(group) }
    /// Deletes the files setup installed for one group. Tools from Homebrew,
    /// the application bundle or a `TWISTER_` override stay where they are.
    public static func remove(_ group:ToolGroup) throws {
        try store.remove(group,protected:ToolStore.overrides(group,environment:overrideEnvironment))
    }
    /// The environment as far as tool overrides apply to this process.
    static var overrideEnvironment:[String:String] { Dependencies.honorsOverrides ? ProcessInfo.processInfo.environment:[:] }
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
                // Kept only while it is still the verified download.
                guard (try? verifyPinned(target.appendingPathComponent(name),tool:name)) != nil else { continue }
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
        // The executable matched its pinned hash; Twister runs it itself.
        Quarantine.remove(from:output)
        if fm.fileExists(atPath:download.path) { try fm.removeItem(at:download) }
    }
    public static func installOffice(token:CancellationToken,progress:@escaping @Sendable (Double?,String)->Void) async throws {
        try token.check();try Task.checkCancellation()
        if officeReady { progress(1,"Office tools are ready.");return }
        let fm=FileManager.default;try fm.createDirectory(at:root,withIntermediateDirectories:true)
        let stage=root.appendingPathComponent(".office-\(UUID().uuidString)",isDirectory:true)
        try fm.createDirectory(at:stage,withIntermediateDirectories:false);defer { try? fm.removeItem(at:stage) }
        let image=stage.appendingPathComponent("LibreOffice.dmg")
        try await CheckedToolDownload.fetch(URL(string:officePackage.url)!,to:image,maximum:400*1024*1024) { progress($0.map{$0*0.8},"Downloading LibreOffice \(officeVersion)…") }
        try verify(image,digest:officePackage.download)
        try token.check();try Task.checkCancellation();progress(nil,"Verifying and preparing office tools…")
        let mount=stage.appendingPathComponent("mount",isDirectory:true);try fm.createDirectory(at:mount,withIntermediateDirectories:false)
        try ProcessRunner.run(URL(fileURLWithPath:"/usr/bin/hdiutil"),["attach","-nobrowse","-readonly","-mountpoint",mount.path,image.path],token:token)
        defer { _ = try? ProcessRunner.run(URL(fileURLWithPath:"/usr/bin/hdiutil"),["detach",mount.path]) }
        let content=stage.appendingPathComponent("content",isDirectory:true);try fm.createDirectory(at:content,withIntermediateDirectories:false)
        try ProcessRunner.run(URL(fileURLWithPath:"/usr/bin/ditto"),[mount.appendingPathComponent("LibreOffice.app").path,content.appendingPathComponent("LibreOffice.app").path],token:token)
        try token.check();try Task.checkCancellation()
        try verifySignature(content.appendingPathComponent("LibreOffice.app"),team:officeTeam)
        Quarantine.remove(from:content)
        let target=root.appendingPathComponent(ToolStore.officeDirectory,isDirectory:true)
        try ToolInstallation.publish(content,to:target) { usable($0.appendingPathComponent("LibreOffice.app/Contents/MacOS/soffice")) }
        progress(1,"Office tools are ready.")
    }
    static let officeVersion="26.8.3"
    /// From the checksum The Document Foundation publishes beside the image.
    static let officePackage=Package(name:"soffice",url:"https://download.documentfoundation.org/libreoffice/stable/26.8.3/mac/aarch64/LibreOffice_26.8.3_MacOS_aarch64.dmg",
                                     download:"de943203795e5057785f65515063e2db5eb60b0bb6d8e2534fec59e5cc5fb988",member:nil)
    /// The Document Foundation's Developer ID team.
    static let officeTeam="7P5S3ZLCN7"

    /// The SHA-256 an installed executable must have.
    static func pinnedDigest(_ tool:String)->String? {
        (mediaPackages+webPackages).first { $0.name == tool }.map { $0.member ?? $0.download }
    }
    static func verifyPinned(_ file:URL,tool:String) throws {
        guard let digest=pinnedDigest(tool) else { throw TwisterError.failed("\(tool) is not a tool that setup installs.") }
        try verify(file,digest:digest)
    }
    /// A Developer ID signature of the given team, valid for the whole bundle.
    static func verifySignature(_ bundle:URL,team:String) throws {
        let failure=TwisterError.failed("The office tools are not signed by their publisher. Nothing was installed or opened.")
        var code:SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL,[],&code)==errSecSuccess,let code else { throw failure }
        var requirement:SecRequirement?
        let text="anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"\(team)\""
        guard SecRequirementCreateWithString(text as CFString,[],&requirement)==errSecSuccess else { throw failure }
        let flags=SecCSFlags(rawValue:kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code,flags,requirement)==errSecSuccess else { throw failure }
    }

    /// Tools in Twister's own folder are checked before their first use in a
    /// session and again after the file changes. The office tools are a whole
    /// bundle whose other files can change without touching the executable,
    /// so their signature is checked before every use.
    static func verifyInstalled(_ executable:URL,tool:String) throws {
        let resolved=executable.resolvingSymlinksInPath()
        let item=tool == "soffice" ? resolved.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent():resolved
        var info=stat()
        guard stat(resolved.path,&info)==0 else { throw TwisterError.missingDependency(tool) }
        let identity=VerifiedTools.Identity(info)
        if tool != "soffice",VerifiedTools.shared.contains(item.path,identity) { return }
        do {
            if tool == "soffice" { try verifySignature(item,team:officeTeam) } else { try verifyPinned(resolved,tool:tool) }
        } catch {
            throw TwisterError.failed("The installed \(tool) no longer matches the verified download. Open tool setup and download it again.")
        }
        if tool != "soffice" { VerifiedTools.shared.insert(item.path,identity) }
    }

    static func verify(_ file:URL,digest:String) throws {
        let input=try FileHandle(forReadingFrom:file);defer{try? input.close()};var hasher=SHA256()
        while let bytes=try input.read(upToCount:1024*1024),!bytes.isEmpty {hasher.update(data:bytes)}
        let actual=hasher.finalize().map{String(format:"%02x",$0)}.joined()
        guard actual == digest else {throw TwisterError.failed("The upstream download checksum did not match. Nothing was installed.")}
    }
}

/// Per-session record of installed tools that passed verification.
final class VerifiedTools:@unchecked Sendable {
    /// Any write to the file, and any change of its mode or owner, moves its
    /// change time, which cannot be set back like the modification time.
    struct Identity:Equatable {
        let device:Int64,inode:UInt64,size:Int64,modified:Int64,changed:Int64
        init(_ info:stat) {
            device=Int64(info.st_dev);inode=UInt64(info.st_ino);size=Int64(info.st_size)
            modified=Int64(info.st_mtimespec.tv_sec)*1_000_000_000+Int64(info.st_mtimespec.tv_nsec)
            changed=Int64(info.st_ctimespec.tv_sec)*1_000_000_000+Int64(info.st_ctimespec.tv_nsec)
        }
    }
    static let shared=VerifiedTools()
    private let lock=NSLock();private var verified:[String:Identity]=[:]
    func contains(_ path:String,_ identity:Identity)->Bool { lock.lock();defer { lock.unlock() };return verified[path]==identity }
    func insert(_ path:String,_ identity:Identity) { lock.lock();verified[path]=identity;lock.unlock() }
    func removeAll() { lock.lock();verified=[:];lock.unlock() }
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
