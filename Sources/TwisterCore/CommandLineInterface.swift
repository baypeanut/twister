import Foundation
import Darwin

public enum TwisterCommandLine {
    static let usage="Usage: twister-cli convert FORMAT [--options JSON] [--json] [--] FILE...\n       twister-cli tool TOOL_ID [--options JSON] [--json] [--] FILE...\n       twister-cli catalog\nExit status: 0 every file was exported, 1 nothing was exported, 3 some files failed and the other exports were kept, 64 usage error."
    /// Some files failed; the exports of the others were kept and printed.
    public static let partialFailureExitCode:Int32=3
    public static func run(arguments args:[String] = CommandLine.arguments,token:CancellationToken = .init(),output:(String)->Void={ print($0) },errorOutput:(String)->Void={ fputs($0+"\n",stderr) }) -> Int32 {
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
    guard args.count>=4 else { output(usage);return 64 }
    guard let invocation=invocation(Array(args.dropFirst(3))) else { errorOutput("--options requires a JSON value.\n\(usage)");return 64 }
    var options=OperationOptions()
    let paths=invocation.paths,jsonOutput=invocation.json
    if let suppliedOptions=invocation.options {
        // Missing keys keep defaults via a JSON overlay encoded from defaults.
        guard var supplied=try JSONSerialization.jsonObject(with:Data(suppliedOptions.utf8)) as? [String:Any] else { throw TwisterError.invalidInput("Options must be a JSON object.") }
        normalizeFileURLs(&supplied)
        var defaults=try JSONSerialization.jsonObject(with:JSONEncoder().encode(options)) as! [String:Any]
        let optionalDefaults:[String:Data]=[
            "imageMetadata":try JSONEncoder().encode(ImageMetadataOptions()),
            "imageFrame":try JSONEncoder().encode(ImageFrameOptions()),
            "imageRedaction":try JSONEncoder().encode(ImageRedactionOptions()),
            "collage":try JSONEncoder().encode(CollageOptions())
        ]
        for (key,data) in optionalDefaults where supplied[key] is [String:Any] { defaults[key]=try JSONSerialization.jsonObject(with:data) }
        options=try JSONDecoder().decode(OperationOptions.self,from:JSONSerialization.data(withJSONObject:mergeDefaults(defaults,with:supplied)))
    }
    let operation:Operation
    if args[1]=="convert" { operation = .convert(args[2]) }
    else if args[1]=="tool",let kind=ToolKind(rawValue:args[2]) { operation = .tool(kind) }
    else { throw TwisterError.invalidInput("Unknown operation.") }
    let report=try ConversionEngine.runBatch(ConversionRequest(inputs:paths.map{URL(fileURLWithPath:$0)},operation:operation,options:options),token:token)
    // Finished files stay on stdout so a script can use them even when others failed.
    for item in report.items { if let reason=item.failure { errorOutput(item.inputs.count==1 ? "\(item.inputs[0].path): \(reason)":reason) } }
    if report.cancelled>0 { errorOutput(TwisterError.cancelled.localizedDescription) }
    let outputs=report.outputs
    if outputs.isEmpty { return 1 }
    if jsonOutput { output(String(decoding:try JSONEncoder().encode(outputs.map(\.path)),as:UTF8.self)) }
    else { for url in outputs { output(url.path) } }
    return report.succeeded==report.items.count ? 0:partialFailureExitCode
} catch { errorOutput(error.localizedDescription);return 1 }

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

    private static func mergeDefaults(_ defaults:[String:Any],with supplied:[String:Any])->[String:Any] {
        defaults.merging(supplied) { old,new in
            if let old=old as? [String:Any],let new=new as? [String:Any] { return mergeDefaults(old,with:new) }
            return new
        }
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
