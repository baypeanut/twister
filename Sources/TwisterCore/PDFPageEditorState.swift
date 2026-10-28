import PDFKit

/// Keeps displayed PDF pages, their source positions, and selection in one value.
/// Replacing a document always clears selection before the page collection changes.
/// The last 50 page edits can be undone; selection alone is not an editing step.
public struct PDFPageEditorState {
    public private(set) var pages:[PDFPage]=[]
    public private(set) var sourceIndexes:[Int]=[]
    public private(set) var selectedPage:Int?
    // Keep immutable source copies and value-only history. A large document
    // does not get another full set of PDFPage copies for every editing step.
    private var sourcePages:[Int:PDFPage]=[:]
    private struct Snapshot {
        let sourceIndexes:[Int]
        let rotations:[Int]
        let selectedPage:Int?
    }
    private var undoHistory:[Snapshot]=[]
    private var redoHistory:[Snapshot]=[]
    private static let historyLimit=50

    public init() {}
    public var hasSelection:Bool { selectedPage.map{pages.indices.contains($0)} ?? false }
    public var canDelete:Bool { hasSelection && pages.count>1 }
    public var canMoveLeft:Bool { hasSelection && (selectedPage ?? 0)>0 }
    public var canMoveRight:Bool { hasSelection && (selectedPage ?? 0)<pages.count-1 }
    public var canUndo:Bool { !undoHistory.isEmpty }
    public var canRedo:Bool { !redoHistory.isEmpty }
    public var rotations:[Int:Int] { Dictionary(uniqueKeysWithValues:pages.enumerated().map{($0.offset,$0.element.rotation)}) }

    public mutating func reset(document:PDFDocument?=nil) {
        selectedPage=nil
        pages=[];sourceIndexes=[];sourcePages=[:];undoHistory=[];redoHistory=[]
        guard let document else { return }
        for index in 0..<document.pageCount {
            guard let source=document.page(at:index)?.copy() as? PDFPage,
                  let page=source.copy() as? PDFPage else { continue }
            sourcePages[index]=source;pages.append(page);sourceIndexes.append(index)
        }
    }
    public mutating func select(_ index:Int) { selectedPage=pages.indices.contains(index) ? index:nil }
    public mutating func rotateSelected() {
        guard let index=selectedPage,pages.indices.contains(index),let page=pages[index].copy() as? PDFPage else { return }
        rememberChange()
        page.rotation=(page.rotation+90)%360;pages[index]=page
    }
    public mutating func duplicateSelected() {
        guard let index=selectedPage,pages.indices.contains(index),sourceIndexes.indices.contains(index),let copy=pages[index].copy() as? PDFPage else { return }
        rememberChange()
        pages.insert(copy,at:index+1);sourceIndexes.insert(sourceIndexes[index],at:index+1)
    }
    public mutating func deleteSelected() {
        guard let index=selectedPage,canDelete,sourceIndexes.indices.contains(index) else { return }
        rememberChange()
        selectedPage=nil
        pages.remove(at:index);sourceIndexes.remove(at:index)
    }
    public mutating func moveSelected(by offset:Int) {
        guard offset == -1 || offset == 1,let index=selectedPage,pages.indices.contains(index) else { return }
        let destination=index+offset
        guard pages.indices.contains(destination),sourceIndexes.indices.contains(index),sourceIndexes.indices.contains(destination) else { return }
        rememberChange()
        pages.swapAt(index,destination);sourceIndexes.swapAt(index,destination);selectedPage=destination
    }

    public mutating func undo() {
        guard let snapshot=undoHistory.last,let restored=materialize(snapshot) else { return }
        redoHistory.append(currentSnapshot)
        undoHistory.removeLast();restore(snapshot,pages:restored)
    }

    public mutating func redo() {
        guard let snapshot=redoHistory.last,let restored=materialize(snapshot) else { return }
        appendUndo(currentSnapshot)
        redoHistory.removeLast();restore(snapshot,pages:restored)
    }

    private var currentSnapshot:Snapshot {
        Snapshot(sourceIndexes:sourceIndexes,rotations:pages.map(\.rotation),selectedPage:selectedPage)
    }
    private mutating func rememberChange() {
        appendUndo(currentSnapshot);redoHistory=[]
    }
    private mutating func appendUndo(_ snapshot:Snapshot) {
        undoHistory.append(snapshot)
        if undoHistory.count>Self.historyLimit { undoHistory.removeFirst(undoHistory.count-Self.historyLimit) }
    }
    private func materialize(_ snapshot:Snapshot)->[PDFPage]? {
        guard snapshot.sourceIndexes.count==snapshot.rotations.count else { return nil }
        var result:[PDFPage]=[];result.reserveCapacity(snapshot.sourceIndexes.count)
        for (source,rotation) in zip(snapshot.sourceIndexes,snapshot.rotations) {
            guard let page=sourcePages[source]?.copy() as? PDFPage else { return nil }
            page.rotation=rotation;result.append(page)
        }
        return result
    }
    private mutating func restore(_ snapshot:Snapshot,pages restored:[PDFPage]) {
        pages=restored;sourceIndexes=snapshot.sourceIndexes
        selectedPage=snapshot.selectedPage.flatMap { pages.indices.contains($0) ? $0:nil }
    }
}
