import Foundation

/// Annotation edits are reversible transactions. A complete drag is one edit,
/// regardless of how many intermediate pointer positions it produces.
public struct ImageAnnotationEditorState {
    public private(set) var annotations:[ImageAnnotation]=[]
    private var undoHistory:[[ImageAnnotation]]=[]
    private var redoHistory:[[ImageAnnotation]]=[]
    private var interactionStart:[ImageAnnotation]?
    private static let limit=50
    public init() {}
    public var canUndo:Bool { !undoHistory.isEmpty || interactionStart.map{$0 != annotations} == true }
    public var canRedo:Bool { interactionStart == nil && !redoHistory.isEmpty }
    public mutating func reset(_ annotations:[ImageAnnotation]=[]) {
        self.annotations=annotations;undoHistory=[];redoHistory=[];interactionStart=nil
    }
    public mutating func append(_ annotation:ImageAnnotation) {
        endInteraction();remember(annotations);annotations.append(annotation)
    }
    public mutating func remove(at index:Int) {
        guard annotations.indices.contains(index) else{return}
        endInteraction();remember(annotations);annotations.remove(at:index)
    }
    public mutating func clear() {
        guard !annotations.isEmpty else{return}
        endInteraction();remember(annotations);annotations=[]
    }
    public mutating func beginInteraction() {
        guard interactionStart == nil else{return}
        interactionStart=annotations
    }
    public mutating func endInteraction() {
        guard let before=interactionStart else{return}
        interactionStart=nil
        if before != annotations {remember(before)}
    }
    public mutating func move(at index:Int,rect:EditRect,points:[ImagePoint]) {
        guard annotations.indices.contains(index),annotations[index].rect != rect || annotations[index].points != points else{return}
        if interactionStart == nil {remember(annotations)}
        annotations[index].rect=rect;annotations[index].points=points
    }
    public mutating func undo() {
        endInteraction()
        guard let before=undoHistory.popLast() else{return}
        redoHistory.append(annotations);annotations=before
    }
    public mutating func redo() {
        endInteraction()
        guard let after=redoHistory.popLast() else{return}
        appendUndo(annotations);annotations=after
    }
    private mutating func remember(_ before:[ImageAnnotation]) {appendUndo(before);redoHistory=[]}
    private mutating func appendUndo(_ value:[ImageAnnotation]) {
        undoHistory.append(value)
        if undoHistory.count>Self.limit {undoHistory.removeFirst(undoHistory.count-Self.limit)}
    }
}
