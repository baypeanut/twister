import Foundation

public enum ConversionEngine {
    /// Operations that turn the whole selection into one result.
    private static let combining:[ToolKind]=[.createPDF,.mergePDF,.createCollage,.joinVideos,.readQRCode]

    /// The independent units of a request. A combining operation is one unit;
    /// every other input is exported, published and cleaned up by itself.
    public static func units(for request: ConversionRequest) -> [[URL]] {
        if case .tool(let tool)=request.operation,combining.contains(tool) { return request.inputs.isEmpty ? []:[request.inputs] }
        return request.inputs.map{[$0]}
    }

    /// All or nothing: one transaction covers every input, so a failure or a
    /// cancellation publishes no output at all. Use runBatch to keep the
    /// files that did finish.
    public static func run(_ request: ConversionRequest, token: CancellationToken = .init(), progress: @escaping ProgressHandler = {_,_ in}) throws -> [URL] {
        guard !request.inputs.isEmpty else { throw TwisterError.invalidInput("Choose at least one file.") }
        let outputs=try export(units(for:request),of:request,token:token,progress:progress)
        progress(1,"Done")
        return outputs
    }

    /// Each unit has its own transaction. A failed unit leaves the finished
    /// outputs of the others in place and nothing of its own. Cancel stops the
    /// remaining units and keeps what was already published. Units run one at
    /// a time: later names depend on earlier publications, and image exports
    /// can start ffmpeg or ExifTool. Throws only for an empty request.
    public static func runBatch(_ request: ConversionRequest, token: CancellationToken = .init(), progress: @escaping ProgressHandler = {_,_ in}, itemChanged: @escaping BatchItemHandler = {_,_ in}) throws -> BatchReport {
        guard !request.inputs.isEmpty else { throw TwisterError.invalidInput("Choose at least one file.") }
        let units=units(for:request)
        var items=units.map{BatchItem(inputs:$0)}
        for (index,inputs) in units.enumerated() {
            if token.isCancelled { items[index].status = .cancelled }
            else {
                itemChanged(index,.running)
                let start=Double(index)/Double(units.count),end=Double(index+1)/Double(units.count)
                do {
                    items[index].status = .succeeded(try export([inputs],of:request,token:token) { value,label in
                        progress(OperationProgress.map(value,from:start,to:end),units.count>1 ? "File \(index+1) of \(units.count) · \(label)":label)
                    })
                } catch { items[index].status = token.isCancelled ? .cancelled:.failed(error.localizedDescription) }
            }
            itemChanged(index,items[index].status)
        }
        if !token.isCancelled { progress(1,"Done") }
        return BatchReport(items:items)
    }

    /// Stages every group, then publishes them together or not at all.
    private static func export(_ groups:[[URL]],of request:ConversionRequest,token:CancellationToken,progress:@escaping ProgressHandler) throws -> [URL] {
        for url in groups.joined() { guard url.isFileURL,FileManager.default.fileExists(atPath:url.path) else { throw TwisterError.invalidInput("File not found: \(url.lastPathComponent)") } }
        try token.check()
        let transaction=ExportTransaction()
        defer { transaction.cleanUp() }
        for (index,inputs) in groups.enumerated() {
            try token.check()
            let destination=request.options.outputDirectory ?? inputs[0].deletingLastPathComponent()
            let area=try transaction.makeArea(destination:destination)
            var options=request.options;options.outputDirectory=area.directory
            let staged=ConversionRequest(inputs:inputs,operation:request.operation,options:options)
            let outputs=try perform(staged,token:token) { value,label in
                let detail = groups.count>1 ? "File \(index+1) of \(groups.count) · \(label)" : label
                progress(OperationProgress.map(value, from: Double(index)/Double(groups.count)*0.98, to: Double(index+1)/Double(groups.count)*0.98),detail)
            }
            try transaction.record(outputs,in:area)
            if groups.count>1 { progress(Double(index+1)/Double(groups.count)*0.98,"Prepared \(index+1) of \(groups.count) files") }
        }
        progress(0.98,"Saving your files…")
        return try transaction.publish(token:token)
    }

    private static func perform(_ request:ConversionRequest,token:CancellationToken,progress:@escaping ProgressHandler) throws -> [URL] {
        var outputs:[URL]=[]
        switch request.operation {
        case .convert(let format):
            for input in request.inputs {
                try token.check();progress(OperationProgress.indeterminate,"Processing \(input.lastPathComponent)…")
                switch FileCategory.detect(input) {
                case .image: outputs += try ImageEngine.convert(input,to:format,options:request.options,token:token)
                case .video,.audio: outputs += try MediaEngine.convert(input,to:format,options:request.options,token:token,progress:progress)
                case .pdf where ["png","jpg"].contains(format): outputs += try PDFEngine.render(input,to:format,options:request.options,token:token,progress:progress)
                default: outputs += try DocumentEngine.convert(input,to:format,options:request.options,token:token)
                }
            }
        case .tool(let tool):
            progress(OperationProgress.indeterminate,tool.title)
            switch tool {
            case .readQRCode: outputs=try QRCodeEngine.export(request.inputs,options:request.options,token:token,progress:progress)
            case .createPDF: outputs=try PDFEngine.create(inputs:request.inputs,options:request.options,token:token,progress:progress)
            case .mergePDF,.splitPDF,.organizePDF: outputs=try PDFEngine.tool(tool,inputs:request.inputs,options:request.options,token:token,progress:progress)
            case .extractArchive:
                for input in request.inputs { try token.check();outputs += try DocumentEngine.extractArchive(input,options:request.options,token:token) }
            case .compress,.removeMetadata:
                for input in request.inputs {
                    try token.check()
                    switch FileCategory.detect(input) {
                    case .image: outputs += try ImageEngine.tool(tool,inputs:[input],options:request.options,token:token)
                    case .video where tool == .removeMetadata && input.pathExtension.lowercased()=="gif":
                        outputs += try ImageEngine.tool(tool,inputs:[input],options:request.options,token:token)
                    case .pdf: outputs += try PDFEngine.tool(tool,inputs:[input],options:request.options,token:token,progress:progress)
                    case .audio,.video: outputs += try MediaEngine.tool(tool,inputs:[input],options:request.options,token:token,progress:progress)
                    default: throw TwisterError.unsupported("This tool does not support \(input.pathExtension.uppercased()) files.")
                    }
                }
            case .editImage,.annotateImage,.frameImage,.cropImage,.createCollage,.redactImage:
                outputs=try ImageEngine.tool(tool,inputs:request.inputs,options:request.options,token:token)
            default: outputs=try MediaEngine.tool(tool,inputs:request.inputs,options:request.options,token:token,progress:progress)
            }
        }
        try token.check();try OutputFiles.validate(outputs)
        return outputs
    }
}
