import Foundation

extension Operation: Equatable {
    /// The catalog's spelling of a format, so "JPEG" and "jpg" name one operation.
    static func normalizedFormat(_ format:String)->String { FeatureCatalog.normalizedExtension(URL(fileURLWithPath:"file."+format.lowercased())) }
    public static func == (left:Operation,right:Operation)->Bool {
        switch (left,right) {
        case (.convert(let a),.convert(let b)):return normalizedFormat(a)==normalizedFormat(b)
        case (.tool(let a),.tool(let b)):return a==b
        default:return false
        }
    }
    /// True when the catalog offers this operation for every one of the files together.
    public func applies(to inputs:[URL])->Bool {
        switch self {
        case .convert(let format):return FeatureCatalog.formats(for:inputs).contains(Self.normalizedFormat(format))
        case .tool(let tool):return FeatureCatalog.tools(for:inputs).contains(tool)
        }
    }
    var json:[String:Any] {
        switch self {
        case .convert(let format):return ["type":"convert","format":Self.normalizedFormat(format)]
        case .tool(let tool):return ["type":"tool","tool":tool.rawValue]
        }
    }
    init?(json:Any?) {
        guard let json=json as? [String:Any] else { return nil }
        if json["type"] as? String=="convert",let format=json["format"] as? String,!format.isEmpty { self = .convert(Self.normalizedFormat(format)) }
        else if json["type"] as? String=="tool",let tool=(json["tool"] as? String).flatMap(ToolKind.init(rawValue:)) { self = .tool(tool) }
        else { return nil }
    }
}

extension OperationOptions {
    /// Decodes a partial JSON object. Keys it does not name keep the value they
    /// have in `base`, and keys this build does not know are ignored.
    public static func overlay(_ supplied:[String:Any],on base:OperationOptions = .init()) throws -> OperationOptions {
        func merge(_ defaults:[String:Any],_ supplied:[String:Any])->[String:Any] {
            defaults.merging(supplied) { old,new in
                if let old=old as? [String:Any],let new=new as? [String:Any] { return merge(old,new) }
                return new
            }
        }
        var defaults=try JSONSerialization.jsonObject(with:JSONEncoder().encode(base)) as! [String:Any]
        // Optional groups are absent from the encoded base; a partial group needs its own defaults.
        let optionalDefaults:[String:Data]=[
            "imageMetadata":try JSONEncoder().encode(ImageMetadataOptions()),
            "imageFrame":try JSONEncoder().encode(ImageFrameOptions()),
            "imageRedaction":try JSONEncoder().encode(ImageRedactionOptions()),
            "collage":try JSONEncoder().encode(CollageOptions())
        ]
        for (key,data) in optionalDefaults where supplied[key] is [String:Any] && defaults[key]==nil { defaults[key]=try JSONSerialization.jsonObject(with:data) }
        return try JSONDecoder().decode(OperationOptions.self,from:JSONSerialization.data(withJSONObject:merge(defaults,supplied)))
    }
}

/// Where a preset saves. A preset without one follows the caller's own choice.
public enum PresetDestination:Equatable,Sendable {
    case besideOriginals
    case folder(URL)
    var json:[String:Any] {
        switch self {
        case .besideOriginals:return ["type":"besideOriginals"]
        case .folder(let url):return ["type":"folder","path":url.path]
        }
    }
    init?(json:Any?) {
        guard let json=json as? [String:Any] else { return nil }
        if json["type"] as? String=="besideOriginals" { self = .besideOriginals }
        else if json["type"] as? String=="folder",let path=json["path"] as? String,!path.isEmpty { self = .folder(URL(fileURLWithPath:(path as NSString).expandingTildeInPath,isDirectory:true)) }
        else { return nil }
    }
}

public enum PresetError:LocalizedError,Equatable {
    case emptyName,duplicateName(String),notFound(String),ambiguous(String),unreadable(String),folderUnavailable(String)
    public var errorDescription:String? {
        switch self {
        case .emptyName:return "Give the preset a name."
        case .duplicateName(let name):return "A preset named “\(name)” already exists."
        case .notFound(let name):return "There is no preset named “\(name)”."
        case .ambiguous(let name):return "More than one preset matches “\(name)”. Use its exact name."
        case .unreadable(let reason):return "This is not a Twister preset. \(reason)"
        case .folderUnavailable(let path):return "The preset’s folder is no longer available: \(path)"
        }
    }
}

/// A named operation with its options, ready to run on any files it applies to.
public struct Preset:Identifiable,Sendable {
    public var id:UUID
    public var name:String
    public var operation:Operation
    public var options:OperationOptions
    public var destination:PresetDestination?

    public init(id:UUID=UUID(),name:String,operation:Operation,options:OperationOptions = .init(),destination:PresetDestination?=nil) {
        self.id=id;self.name=Self.cleaned(name);self.operation=operation;self.options=Self.storable(options);self.destination=destination
    }
    public static func cleaned(_ name:String)->String { name.split(whereSeparator:\.isNewline).joined(separator:" ").trimmingCharacters(in:.whitespaces) }
    /// A file's password, a one-time folder and the caller's Finder preference do not belong to a preset.
    public static func storable(_ options:OperationOptions)->OperationOptions {
        var options=options;options.password="";options.outputDirectory=nil;options.revealInFinder=OperationOptions().revealInFinder
        return options
    }
    public func applies(to inputs:[URL])->Bool { operation.applies(to:inputs) }
    /// A preset from a file keeps its operation and settings only. Where it
    /// saves, and files it would read from this Mac, stay the user's choice.
    public var imported:Preset {
        var preset=self
        if case .folder = preset.destination { preset.destination=nil }
        var options=preset.options
        options.visualizationImage=nil
        options.imageFrame?.backgroundImage=nil
        if options.imageFrame?.backdrop == .image { options.imageFrame?.backdrop = .solid }
        options.collage?.backgroundImage=nil
        options.imageAnnotations.removeAll { $0.imageURL != nil }
        preset.options=options
        return preset
    }

    /// The request this preset makes for the files. `fallback` is the caller's
    /// own destination and is used when the preset does not name one.
    public func request(for inputs:[URL],fallback:URL?=nil) throws -> ConversionRequest {
        var options=options
        switch destination {
        case .folder(let url):
            var directory:ObjCBool=false
            guard FileManager.default.fileExists(atPath:url.path,isDirectory:&directory),directory.boolValue else { throw PresetError.folderUnavailable(url.path) }
            options.outputDirectory=url
        case .besideOriginals:options.outputDirectory=nil
        case nil:options.outputDirectory=fallback
        }
        return ConversionRequest(inputs:inputs,operation:operation,options:options)
    }

    var json:[String:Any] {
        var result:[String:Any]=["id":id.uuidString,"name":name,"operation":operation.json]
        if let data=try? JSONEncoder().encode(options),let object=try? JSONSerialization.jsonObject(with:data) { result["options"]=object }
        if let destination { result["destination"]=destination.json }
        return result
    }
    /// Options an older build did not save keep their defaults; fields a newer
    /// build added are ignored. Throws when the name or the operation cannot be read.
    init(json:Any) throws {
        guard let json=json as? [String:Any] else { throw PresetError.unreadable("A preset must be a JSON object.") }
        let name=Self.cleaned(json["name"] as? String ?? "")
        guard !name.isEmpty else { throw PresetError.unreadable("The preset has no name.") }
        guard let operation=Operation(json:json["operation"]) else { throw PresetError.unreadable("“\(name)” uses an operation this Twister does not have.") }
        let options:OperationOptions
        do { options=try OperationOptions.overlay(json["options"] as? [String:Any] ?? [:]) }
        catch { throw PresetError.unreadable("“\(name)” has options this Twister cannot read.") }
        self.init(id:(json["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(),name:name,operation:operation,options:options,destination:PresetDestination(json:json["destination"]))
    }
}

/// The saved presets in their order. Entries this build cannot read are kept
/// as they were, so saving does not drop a preset made by a newer Twister.
public struct PresetLibrary {
    public static let currentVersion=1
    public private(set) var presets:[Preset]=[]
    var unreadable:[Any]=[]
    var version=PresetLibrary.currentVersion
    /// How many saved entries this build could not read.
    public var unreadableCount:Int { unreadable.count }
    /// Where a damaged presets file was moved before starting again.
    public internal(set) var preservedCorruptFile:URL?
    public init(presets:[Preset]=[]) { for preset in presets { _=try? add(preset) } }

    private func key(_ name:String)->String { Preset.cleaned(name).folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX")) }
    public func isNameTaken(_ name:String,except id:UUID?=nil)->Bool { presets.contains { $0.id != id && key($0.name)==key(name) } }
    /// "Web JPEG", then "Web JPEG 2", "Web JPEG 3"…
    public func availableName(_ name:String)->String {
        let base=Preset.cleaned(name)
        guard isNameTaken(base) else { return base }
        var number=2
        while isNameTaken("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }
    private func validated(_ name:String,except id:UUID?=nil) throws -> String {
        let name=Preset.cleaned(name)
        guard !name.isEmpty else { throw PresetError.emptyName }
        guard !isNameTaken(name,except:id) else { throw PresetError.duplicateName(name) }
        return name
    }
    public subscript(id:UUID)->Preset? { presets.first{$0.id==id} }
    /// An exact name wins; otherwise one name that differs only by case or accents, or an identifier.
    public func find(_ reference:String) throws -> Preset {
        if let exact=presets.first(where:{$0.name==reference}) { return exact }
        let close=presets.filter { key($0.name)==key(reference) }
        if close.count>1 { throw PresetError.ambiguous(reference) }
        if let match=close.first ?? UUID(uuidString:reference).flatMap({self[$0]}) { return match }
        throw PresetError.notFound(reference)
    }
    public func applicable(to inputs:[URL])->[Preset] { inputs.isEmpty ? []:presets.filter { $0.applies(to:inputs) } }

    @discardableResult public mutating func add(_ preset:Preset) throws -> Preset {
        var preset=preset;preset.name=try validated(preset.name)
        if self[preset.id] != nil { preset.id=UUID() }
        presets.append(preset);return preset
    }
    public mutating func rename(_ id:UUID,to name:String) throws {
        guard let index=presets.firstIndex(where:{$0.id==id}) else { return }
        presets[index].name=try validated(name,except:id)
    }
    @discardableResult public mutating func duplicate(_ id:UUID)->Preset? {
        guard let index=presets.firstIndex(where:{$0.id==id}) else { return nil }
        var copy=presets[index];copy.id=UUID();copy.name=availableName(copy.name)
        presets.insert(copy,at:index+1);return copy
    }
    public mutating func remove(_ id:UUID) { presets.removeAll{$0.id==id} }
    /// Moves a preset by a number of places, stopping at either end.
    public mutating func move(_ id:UUID,by offset:Int) {
        guard let index=presets.firstIndex(where:{$0.id==id}) else { return }
        let preset=presets.remove(at:index)
        presets.insert(preset,at:min(presets.count,max(0,index+offset)))
    }
    /// Adds presets from an exported file or a single preset object. A name
    /// that is taken gets a number instead of replacing the saved preset.
    /// Imported presets save where the user chooses and name no local files.
    @discardableResult public mutating func importPresets(from data:Data) throws -> [Preset] {
        guard let object=try? JSONSerialization.jsonObject(with:data) else { throw PresetError.unreadable("The file is not valid JSON.") }
        let entries:[Any]
        if let file=object as? [String:Any],let list=file["presets"] as? [Any] { entries=list }
        else if object is [String:Any] { entries=[object] }
        else { throw PresetError.unreadable("Expected a preset or a list of presets.") }
        guard !entries.isEmpty else { throw PresetError.unreadable("The file has no presets.") }
        // Nothing is added unless every entry can be read.
        var imported:[Preset]=[]
        for var preset in try entries.map({ try Preset(json:$0).imported }) {
            preset.name=availableName(preset.name)
            imported.append(try add(preset))
        }
        return imported
    }
    public static func exportData(_ presets:[Preset]) throws -> Data {
        try JSONSerialization.data(withJSONObject:["version":currentVersion,"presets":presets.map(\.json)],options:[.prettyPrinted,.sortedKeys])
    }
    var data:Data { get throws {
        try JSONSerialization.data(withJSONObject:["version":max(version,Self.currentVersion),"presets":presets.map(\.json)+unreadable],options:[.prettyPrinted,.sortedKeys])
    } }
}

/// One JSON file shared by the app and twister-cli.
public struct PresetStore:Sendable {
    public let url:URL
    public init(url:URL) { self.url=url }
    /// ~/Library/Application Support/Twister/Presets.json, or the file named by TWISTER_PRESETS_FILE.
    public static var standard:PresetStore {
        if let path=ProcessInfo.processInfo.environment["TWISTER_PRESETS_FILE"],!path.isEmpty { return .init(url:URL(fileURLWithPath:(path as NSString).expandingTildeInPath)) }
        return .init(url:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Twister/Presets.json"))
    }

    /// A missing file is an empty library. A file that is not a presets file is
    /// moved aside under a new name, never deleted, and reported in the result.
    /// Throws only when the file exists and cannot be read or moved.
    public func load() throws -> PresetLibrary {
        guard FileManager.default.fileExists(atPath:url.path) else { return PresetLibrary() }
        let data=try Data(contentsOf:url)
        var library=PresetLibrary()
        guard let file=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let entries=file["presets"] as? [Any] else {
            library.preservedCorruptFile=try preserve()
            return library
        }
        library.version=(file["version"] as? Int) ?? PresetLibrary.currentVersion
        for entry in entries {
            // A name repeated by hand in the file gets a number instead of hiding a preset.
            if var preset=try? Preset(json:entry) { preset.name=library.availableName(preset.name);_=try? library.add(preset) }
            else { library.unreadable.append(entry) }
        }
        return library
    }
    private func preserve() throws -> URL {
        let stamp=ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"")
        let folder=url.deletingLastPathComponent(),base=url.deletingPathExtension().lastPathComponent
        var target=folder.appendingPathComponent("\(base).corrupt-\(stamp).json"),number=2
        while FileManager.default.fileExists(atPath:target.path) { target=folder.appendingPathComponent("\(base).corrupt-\(stamp)-\(number).json");number += 1 }
        try FileManager.default.moveItem(at:url,to:target)
        return target
    }
    /// Replaces the file in one step, so a reader never sees half of it.
    public func save(_ library:PresetLibrary) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try library.data.write(to:url,options:.atomic)
    }
    /// Loads the current file, applies the change and saves it.
    @discardableResult public func update<T>(_ change:(inout PresetLibrary) throws -> T) throws -> T {
        var library=try load()
        let result=try change(&library)
        try save(library);return result
    }
}
