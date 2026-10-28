import AppKit
import TwisterCore

/// Exercises bookmark persistence and real exports using generated files and an
/// isolated preference suite. It never opens Finder, a picker or another app.
@MainActor final class OutputDestinationSmoke:NSObject,NSApplicationDelegate {
    private let output:URL
    private var checks:[String]=[]
    init(output:URL) { self.output=output }

    func applicationDidFinishLaunching(_ notification:Notification) {
        Task {
            var failure:String?
            do { try await run() } catch { failure=error.localizedDescription }
            let report:[String:Any]=["passed":failure == nil,"checks":checks,
                "error":failure as Any? ?? NSNull(),
                "scope":"Own-process generated image exports, isolated output-folder preferences and security-scoped bookmarks. No Finder, picker, global input or external services."]
            if FileManager.default.fileExists(atPath:output.appendingPathComponent(".twister-output-destination").path),
               let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {
                try? data.write(to:output.appendingPathComponent("output-destination.json"),options:.atomic)
            }
            print("OUTPUT_DESTINATION \(failure == nil ? "PASS":"FAIL") \(checks.count)")
            if let failure { fputs(failure+"\n",stderr) }
            exit(failure == nil ? 0:1)
        }
    }

    private func check(_ condition:Bool,_ message:String)throws {
        guard condition else { throw NSError(domain:"Twister Output Folder QA",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
        checks.append(message)
    }
    private func fails(_ action:()throws->Void)->Bool {
        do { try action();return false } catch { return true }
    }
    private func sameFolder(_ output:URL,_ directory:URL)->Bool {
        output.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL
    }
    private func finish(_ state:AppState)async throws {
        let deadline=Date().addingTimeInterval(15)
        while state.working && Date()<deadline { try await Task.sleep(nanoseconds:20_000_000) }
        try check(!state.working,"The image export completes within its bounded own-process fixture")
        if let error=state.error { throw NSError(domain:"Twister Output Folder QA",code:3,userInfo:[NSLocalizedDescriptionKey:error]) }
    }

    private func run()async throws {
        let manager=FileManager.default,marker=output.appendingPathComponent(".twister-output-destination")
        if manager.fileExists(atPath:output.path),!manager.fileExists(atPath:marker.path),
           try !manager.contentsOfDirectory(atPath:output.path).isEmpty {
            throw NSError(domain:"Twister Output Folder QA",code:2,userInfo:[NSLocalizedDescriptionKey:"Choose an empty output-folder QA directory."])
        }
        try manager.createDirectory(at:output,withIntermediateDirectories:true)
        try Data("Twister own-process output-folder QA\n".utf8).write(to:marker,options:.atomic)
        let suite="Twister.OutputQA."+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set(false,forKey:"reveal")
        let fixture=try OutputFiles.temporaryDirectory()
        defer { try? manager.removeItem(at:fixture) }
        let sourceFolder=fixture.appendingPathComponent("Originals",isDirectory:true)
        let first=fixture.appendingPathComponent("First destination",isDirectory:true)
        let second=fixture.appendingPathComponent("Second destination",isDirectory:true)
        let explicit=fixture.appendingPathComponent("Explicit destination",isDirectory:true)
        let missing=fixture.appendingPathComponent("Removed destination",isDirectory:true)
        for directory in [sourceFolder,first,second,explicit,missing] { try manager.createDirectory(at:directory,withIntermediateDirectories:true) }
        let source=sourceFolder.appendingPathComponent("Original.png")
        guard let context=CGContext(data:nil,width:24,height:24,bitsPerComponent:8,bytesPerRow:0,
                                    space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw TwisterError.failed("Could not create the generated image fixture.")
        }
        context.setFillColor(CGColor(red:0.2,green:0.5,blue:0.8,alpha:1));context.fill(CGRect(x:0,y:0,width:24,height:24))
        guard let image=context.makeImage() else { throw TwisterError.failed("Could not draw the generated image fixture.") }
        try ImageEngine.write(image,to:source)
        let sourceBytes=try Data(contentsOf:source)
        let existing=first.appendingPathComponent("Original.jpg"),existingBytes=Data("Keep this existing destination file\n".utf8)
        try existingBytes.write(to:existing)
        let state=AppState(defaults:defaults);state.inputs=[source]
        var options=OperationOptions();options.preserveMetadata=false;options.revealInFinder=false

        try check(!state.outputDestination.usesCustomFolder && (try state.outputDestination.snapshot().directory)==nil,"A fresh profile saves beside each original")
        try state.outputDestination.choose(first)
        let restored=OutputDestinationPreferences(defaults:defaults)
        let persisted=try restored.snapshot()
        try check(restored.usesCustomFolder && persisted.directory.map{sameFolder($0.appendingPathComponent("result"),first)} == true,"The chosen folder and its security-scoped bookmark survive preference reload")
        restored.useOriginalFolders()
        let reset=OutputDestinationPreferences(defaults:defaults)
        try check(!reset.usesCustomFolder && (try reset.snapshot().directory)==nil,"Beside originals clears the saved destination persistently")
        try check(manager.fileExists(atPath:first.path) && (try Data(contentsOf:source))==sourceBytes,"Resetting the destination keeps the folder and original file intact")

        try state.outputDestination.choose(first)
        state.execute(.convert("jpg"),options:options)
        try check(state.working,"The destination is captured before asynchronous conversion begins")
        // UI controls are disabled while working. A direct model mutation here
        // deliberately challenges the immutable snapshot used by this job.
        try state.outputDestination.choose(second)
        try await finish(state)
        try check(state.outputs.count==1 && state.outputs.allSatisfy{sameFolder($0,first)},"A running export keeps its captured destination when later preferences change")
        try check(state.outputs.first != existing && (try Data(contentsOf:existing))==existingBytes,"An existing destination file is preserved and the export receives a unique name")
        try check(!manager.fileExists(atPath:sourceFolder.appendingPathComponent("Original.jpg").path),"A custom-folder export does not also write beside the original")
        if let result=state.outputs.first { _=try ImageEngine.load(result) }
        try check(state.outputs.first != nil,"The custom-folder result is a decodable image")

        state.execute(.convert("jpg"),options:options);try await finish(state)
        try check(state.outputs.count==1 && state.outputs.allSatisfy{sameFolder($0,second)},"The next job uses the newly selected destination")
        var override=options;override.outputDirectory=explicit
        state.execute(.convert("jpg"),options:override);try await finish(state)
        try check(state.outputs.count==1 && state.outputs.allSatisfy{sameFolder($0,explicit)},"An explicit request destination takes priority over the remembered folder")

        try state.outputDestination.choose(missing)
        let captured=try state.outputDestination.snapshot()
        try manager.removeItem(at:missing)
        var entered=false
        try check(fails{try captured.withAccess { entered=true } } && !entered,"A folder removed after capture is rejected before the export can recreate it")
        state.execute(.tool(.editImage),options:options,inputs:[source])
        try check(!state.working && state.error != nil && state.outputs.isEmpty,"A missing saved folder produces a clear error without beginning a job")
        try check(state.activeTool == .editImage && state.activeInputs == [source],"Output-folder errors retain editor context so the user can see the failure")
        try check(!manager.fileExists(atPath:missing.path) && !manager.fileExists(atPath:sourceFolder.appendingPathComponent("Original.jpg").path),"A missing destination is neither recreated nor silently replaced with the original's folder")
        state.execute(.convert("jpg"),options:override);try await finish(state)
        try check(state.outputs.count==1 && state.outputs.allSatisfy{sameFolder($0,explicit)},"An explicit request remains usable when the remembered folder is missing")

        state.outputDestination.useOriginalFolders()
        state.execute(.convert("jpg"),options:options);try await finish(state)
        try check(state.outputs.count==1 && state.outputs.allSatisfy{sameFolder($0,sourceFolder)},"Restoring Beside originals takes effect on the next real export")
        try check((try Data(contentsOf:source))==sourceBytes && (try Data(contentsOf:existing))==existingBytes,"All destination changes preserve both original and existing destination bytes")
        try check(fails{try state.outputDestination.choose(source)} && !state.outputDestination.usesCustomFolder,"A file cannot replace the chosen output-folder preference")

        defaults.set(Data("Invalid saved destination".utf8),forKey:"outputDestination.v1")
        let damaged=OutputDestinationPreferences(defaults:defaults)
        try check(damaged.usesCustomFolder && fails{_=try damaged.snapshot()},"An unreadable saved bookmark requests renewal instead of falling back to another destination")
        damaged.useOriginalFolders()
        try check(!OutputDestinationPreferences(defaults:defaults).usesCustomFolder,"Reset also recovers from a damaged saved destination")
    }
}
