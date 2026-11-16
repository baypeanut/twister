import AppKit
import SwiftUI

enum OutputDestinationError:LocalizedError {
    case permissionNeedsRenewal,unavailable,notDirectory,notWritable
    var errorDescription:String? {
        switch self {
        case .permissionNeedsRenewal:return "The saved output-folder permission needs to be renewed. Choose the folder again."
        case .unavailable:return "Your output folder is no longer available. Choose it again, or save beside the originals."
        case .notDirectory:return "Choose a folder for the results."
        case .notWritable:return "The output folder is not writable. Choose another folder, or save beside the originals."
        }
    }
}

private func validateOutputDirectory(_ url:URL)throws {
    guard url.isFileURL,FileManager.default.fileExists(atPath:url.path) else { throw OutputDestinationError.unavailable }
    let values:URLResourceValues
    do { values=try url.resourceValues(forKeys:[.isDirectoryKey]) }
    catch { throw OutputDestinationError.unavailable }
    guard values.isDirectory == true else { throw OutputDestinationError.notDirectory }
    guard FileManager.default.isWritableFile(atPath:url.path) else { throw OutputDestinationError.notWritable }
}

/// One immutable selection belongs to each job. The selected bookmark remains
/// active for the complete conversion, staging and publication transaction.
struct OutputDestinationSnapshot:Sendable {
    let directory:URL?
    private let scopedURL:URL?
    fileprivate init(directory:URL?,scopedURL:URL?=nil) { self.directory=directory;self.scopedURL=scopedURL }
    static let besideOriginals=OutputDestinationSnapshot(directory:nil)
    func withAccess<T>(_ action:() throws->T)throws->T {
        let started=scopedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if started { scopedURL?.stopAccessingSecurityScopedResource() } }
        if let scopedURL { try validateOutputDirectory(scopedURL) }
        return try action()
    }
}

@MainActor final class OutputDestinationPreferences:ObservableObject {
    private struct Selection:Codable { let path:String;let bookmark:Data }
    private static let key="outputDestination.v1"
    private let defaults:UserDefaults
    private var selection:Selection?
    private var invalidSavedSelection=false
    @Published private(set) var folder:URL?
    @Published private(set) var selectionIssue:String?
    var usesCustomFolder:Bool { selection != nil || invalidSavedSelection }

    init(defaults:UserDefaults) {
        self.defaults=defaults
        if let object=defaults.object(forKey:Self.key) {
            if let data=object as? Data,let saved=try? JSONDecoder().decode(Selection.self,from:data) {
                selection=saved;folder=URL(fileURLWithPath:saved.path,isDirectory:true)
            } else {
                invalidSavedSelection=true
                selectionIssue=OutputDestinationError.permissionNeedsRenewal.localizedDescription
            }
        }
    }

    func choose(_ url:URL)throws {
        let started=url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        try validateOutputDirectory(url)
        let bookmark=try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
        let saved=Selection(path:url.standardizedFileURL.path,bookmark:bookmark)
        let data=try JSONEncoder().encode(saved)
        defaults.set(data,forKey:Self.key)
        selection=saved;invalidSavedSelection=false;folder=url.standardizedFileURL;selectionIssue=nil
    }

    func useOriginalFolders() {
        defaults.removeObject(forKey:Self.key)
        selection=nil;invalidSavedSelection=false;folder=nil;selectionIssue=nil
    }

    func snapshot(explicitDirectory:URL?=nil)throws->OutputDestinationSnapshot {
        // An explicit request remains authoritative even if a remembered default
        // is unavailable. Its own caller may intentionally create a new folder.
        if let explicitDirectory { return .init(directory:explicitDirectory) }
        guard usesCustomFolder else { return .init(directory:nil) }
        do {
            guard !invalidSavedSelection,let selection else { throw OutputDestinationError.permissionNeedsRenewal }
            var stale=false
            let resolved:URL
            do {
                resolved=try URL(resolvingBookmarkData:selection.bookmark,options:[.withSecurityScope,.withoutUI],relativeTo:nil,bookmarkDataIsStale:&stale)
            } catch { throw OutputDestinationError.permissionNeedsRenewal }
            guard !stale else { throw OutputDestinationError.permissionNeedsRenewal }
            let result=OutputDestinationSnapshot(directory:resolved,scopedURL:resolved)
            try result.withAccess { }
            selectionIssue=nil
            return result
        } catch {
            selectionIssue=error.localizedDescription
            throw error
        }
    }
}

struct OutputDestinationControl:View {
    @ObservedObject var state:AppState
    @ObservedObject private var destination:OutputDestinationPreferences
    @State private var pickerError:String?
    private let compact:Bool
    init(state:AppState,compact:Bool=false) { self.state=state;self.destination=state.outputDestination;self.compact=compact }
    private var issue:String? { pickerError ?? destination.selectionIssue }
    @ViewBuilder private var destinationLabel:some View {
        if destination.usesCustomFolder {
            if let folder=destination.folder { Text(verbatim:folder.lastPathComponent).lineLimit(1).truncationMode(.middle).help(folder.path) }
            else { LText("Choose folder again") }
        } else { LText("Beside originals") }
    }
    @ViewBuilder private var menuItems:some View {
        Button(action:chooseFolder) { LText("Choose Folder…") }
        if destination.usesCustomFolder {
            Button { guard !state.working else{return};destination.useOriginalFolders();pickerError=nil } label:{LText("Beside originals")}
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:4) {
            HStack(spacing:8) {
                if !compact { LText("Save to").foregroundStyle(.secondary) }
                Menu { menuItems } label:{
                    if compact { Label { destinationLabel } icon:{ Image(systemName:"folder") } } else { destinationLabel }
                }
                .fixedSize()
                .accessibilityLabel(L10n.text("Change output folder"))
                .accessibilityIdentifier("OutputDestination")
                if compact,let issue {
                    Image(systemName:"exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                        .help(L10n.text(issue)).accessibilityLabel(L10n.text(issue))
                }
            }.disabled(state.working)
            if !compact,let error=issue {
                LText(error).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }.frame(maxWidth:compact ? 220:.infinity,alignment:.leading)
        .onChange(of:destination.folder) { _ in pickerError=nil }
        .onChange(of:destination.usesCustomFolder) { _ in pickerError=nil }
    }
    private func chooseFolder() {
        guard !state.working else { return }
        let panel=NSOpenPanel();panel.title=L10n.text("Save results to");panel.prompt=L10n.text("Use folder")
        panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.canCreateDirectories=true
        panel.directoryURL=destination.folder
        if panel.runModal() == .OK,let url=panel.url {
            do { try destination.choose(url);pickerError=nil }
            catch { pickerError=error.localizedDescription }
        }
    }
}
