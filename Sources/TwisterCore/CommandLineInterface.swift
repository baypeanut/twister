import Foundation
import Darwin

public enum TwisterCommandLine {
    static let usage="Usage: twister-cli convert FORMAT [--options JSON] [--json] [--] FILE...\n       twister-cli tool TOOL_ID [--options JSON] [--json] [--] FILE...\n       twister-cli preset list [--json]\n       twister-cli preset run NAME [--options JSON] [--json] [--] FILE...\n       twister-cli preset export NAME\n       twister-cli preset import FILE\n       twister-cli catalog\nExit status: 0 every file was exported, 1 nothing was exported, 3 some files failed and the other exports were kept, 64 usage error."
    /// Some files failed; the exports of the others were kept and printed.
    public static let partialFailureExitCode:Int32=3
    public static func run(arguments args:[String] = CommandLine.arguments,token:CancellationToken = .init(),presets:PresetStore = .standard,output:(String)->Void={ print($0) },errorOutput:(String)->Void={ fputs($0+"\n",stderr) }) -> Int32 {
do {
    if args.count==2,args[1]=="catalog" {
        let data=try JSONSerialization.data(withJSONObject:["conversionMatrix":FeatureCatalog.conversionMatrix,"tools":ToolKind.allCases.map(\.rawValue)],options:[.prettyPrinted,.sortedKeys]);output(String(decoding:data,as:UTF8.self));return 0
    }
    if args.count==3,args[1]=="inspect" {
        let input=URL(fileURLWithPath:args[2]),category=FileCategory.detect(input)
        var result:[String:Any]=["category":category.rawValue]
        switch category {
        case .image:let cg=try ImageEngine.load(input);result["width"]=cg.width;result["height"]=cg.height
        case .pdf:let pdf=try PDFEngine.open(input);result["pages"]=pdf.pageCount;result["text"]=pdf.string ?? ""
        case .audio,.video:let info=try MediaEngine.inspect(input,token:token);result["duration"]=info.duration;result["hasAudio"]=info.hasAudio;result["hasVideo"]=info.hasVideo;result["width"]=info.video?.width;result["height"]=info.video?.height;result["channels"]=info.audio?.channels
        default:break
        }
        output(String(decoding:try JSONSerialization.data(withJSONObject:result,options:.sortedKeys),as:UTF8.self));return 0
    }
    if args.count==2,args[1]=="dependencies" {
        var result:[String:String]=[:];for name in ["ffmpeg","ffprobe","soffice","exiftool"] { result[name]=try Dependencies.executable(name).path };output(String(decoding:try JSONSerialization.data(withJSONObject:result,options:.sortedKeys),as:UTF8.self));return 0
    }
    if args.count>=2,args[1]=="preset" { return try preset(Array(args.dropFirst(2)),store:presets,token:token,output:output,errorOutput:errorOutput) }
    guard args.count>=4 else { output(usage);return 64 }
    guard let invocation=invocation(Array(args.dropFirst(3))) else { errorOutput("--options requires a JSON value.\n\(usage)");return 64 }
    let operation:Operation
    if args[1]=="convert" { operation = .convert(args[2]) }
    else if args[1]=="tool",let kind=ToolKind(rawValue:args[2]) { operation = .tool(kind) }
    else { throw TwisterError.invalidInput("Unknown operation.") }
    let request=ConversionRequest(inputs:invocation.paths.map{URL(fileURLWithPath:$0)},operation:operation,options:try options(invocation.options))
    return try export(request,json:invocation.json,token:token,output:output,errorOutput:errorOutput)
} catch { errorOutput(error.localizedDescription);return 1 }

    }

    /// Missing keys keep the values of `base` via a JSON overlay.
    private static func options(_ supplied:String?,on base:OperationOptions = .init()) throws -> OperationOptions {
        guard let supplied else { return base }
        guard var object=try JSONSerialization.jsonObject(with:Data(supplied.utf8)) as? [String:Any] else { throw TwisterError.invalidInput("Options must be a JSON object.") }
        normalizeFileURLs(&object)
        return try OperationOptions.overlay(object,on:base)
    }

    private static func export(_ request:ConversionRequest,json:Bool,token:CancellationToken,output:(String)->Void,errorOutput:(String)->Void) throws -> Int32 {
        let report=try ConversionEngine.runBatch(request,token:token)
        // Finished files stay on stdout so a script can use them even when others failed.
        for item in report.items { if let reason=item.failure { errorOutput(item.inputs.count==1 ? "\(item.inputs[0].path): \(reason)":reason) } }
        if report.cancelled>0 { errorOutput(TwisterError.cancelled.localizedDescription) }
        let outputs=report.outputs
        if outputs.isEmpty { return 1 }
        if json { output(String(decoding:try JSONEncoder().encode(outputs.map(\.path)),as:UTF8.self)) }
        else { for url in outputs { output(url.path) } }
        return report.succeeded==report.items.count ? 0:partialFailureExitCode
    }

    private static func preset(_ words:[String],store:PresetStore,token:CancellationToken,output:(String)->Void,errorOutput:(String)->Void) throws -> Int32 {
        func load() throws -> PresetLibrary {
            let library=try store.load()
            if let moved=library.preservedCorruptFile { errorOutput("The presets file could not be read and was kept as \(moved.path).") }
            return library
        }
        switch words.first {
        case "list":
            guard words.count==1 || words.dropFirst()==["--json"] else { break }
            let presets=try load().presets
            if words.count==2 { output(String(decoding:try PresetLibrary.exportData(presets),as:UTF8.self)) }
            else { for preset in presets { output("\(preset.name)\t\(preset.operation.title)") } }
            return 0
        case "export":
            guard words.count==2 else { break }
            output(String(decoding:try PresetLibrary.exportData([try load().find(words[1])]),as:UTF8.self));return 0
        case "import":
            guard words.count==2 else { break }
            let data=try Data(contentsOf:URL(fileURLWithPath:words[1]))
            for preset in try store.update({ try $0.importPresets(from:data) }) { output(preset.name) }
            return 0
        case "run":
            guard words.count>=2 else { break }
            guard let invocation=invocation(Array(words.dropFirst(2))) else { errorOutput("--options requires a JSON value.\n\(usage)");return 64 }
            guard !invocation.paths.isEmpty else { break }
            let preset=try load().find(words[1])
            var request=try preset.request(for:invocation.paths.map{URL(fileURLWithPath:$0)})
            request.options=try options(invocation.options,on:request.options)
            return try export(request,json:invocation.json,token:token,output:output,errorOutput:errorOutput)
        default:break
        }
        output(usage);return 64
    }

    struct Invocation:Equatable { var paths:[String]=[],json=false,options:String? }
    /// Everything after "--" is a file, so names such as "--json" stay usable.
    /// Returns nil when --options is the last word and has no value.
    static func invocation(_ words:[String]) -> Invocation? {
        var result=Invocation(),words=words[...],literal=false
        while let word=words.popFirst() {
            if literal { result.paths.append(word) }
            else if word=="--" { literal=true }
            else if word=="--json" { result.json=true }
            else if word=="--options" {
                guard let value=words.popFirst() else { return nil }
                result.options=value
            } else { result.paths.append(word) }
        }
        return result
    }

    private static func normalizeFileURLs(_ options:inout [String:Any]) {
        func fileURL(_ value:Any?)->Any? {
            guard let value=value as? String,URL(string:value)?.scheme==nil else { return value }
            return URL(fileURLWithPath:(value as NSString).expandingTildeInPath).absoluteString
        }
        for key in ["outputDirectory","visualizationImage"] { if let value=options[key] { options[key]=fileURL(value) } }
        for key in ["imageFrame","collage"] { if var settings=options[key] as? [String:Any],let value=settings["backgroundImage"] { settings["backgroundImage"]=fileURL(value);options[key]=settings } }
        if var annotations=options["imageAnnotations"] as? [[String:Any]] { for i in annotations.indices { if let value=annotations[i]["imageURL"] { annotations[i]["imageURL"]=fileURL(value) } };options["imageAnnotations"]=annotations }
    }
}

/// Routes termination signals to a CancellationToken, so an interrupted
/// command stops its helpers and removes staged exports before it exits.
public final class SignalCancellation {
    private let lock=NSLock()
    private var sources:[DispatchSourceSignal]=[],received:Int32?
    private let signals:[Int32]
    public init(token:CancellationToken,signals:[Int32]=[SIGINT,SIGTERM]) {
        self.signals=signals
        for number in signals {
            // The default action would end the process before cleanup runs.
            Darwin.signal(number,SIG_IGN)
            let source=DispatchSource.makeSignalSource(signal:number,queue:.global())
            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.lock.lock();let repeated=self.received != nil;self.received=self.received ?? number;self.lock.unlock()
                // A second signal means cleanup is not finishing; stop at once.
                if repeated { _exit(128+number) }
                token.cancel()
            }
            source.resume();sources.append(source)
        }
    }
    deinit { for source in sources { source.cancel() };for number in signals { Darwin.signal(number,SIG_DFL) } }
    public var receivedSignal:Int32? { lock.lock();defer{lock.unlock()};return received }
    /// Shells expect 128 plus the signal number from an interrupted command.
    public func exitCode(_ code:Int32)->Int32 { receivedSignal.map{128+$0} ?? code }
}
