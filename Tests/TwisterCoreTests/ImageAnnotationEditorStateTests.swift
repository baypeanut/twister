import XCTest
@testable import TwisterCore

final class ImageAnnotationEditorStateTests:XCTestCase {
    private func mark(_ x:Double)->ImageAnnotation {
        var value=ImageAnnotation(kind:.freehand,rect:.init(x:x,y:10,width:20,height:30))
        value.points=[.init(x:x,y:10),.init(x:x+20,y:40)];value.text="Türkçe not";value.opacity=0.7
        return value
    }
    func testUndoDeleteRestoresTheDeletedMarkInsteadOfRemovingAnother() {
        let first=mark(5),second=mark(50)
        var editor=ImageAnnotationEditorState();editor.append(first);editor.append(second)
        editor.remove(at:0);XCTAssertEqual(editor.annotations,[second])
        editor.undo();XCTAssertEqual(editor.annotations,[first,second])
        editor.redo();XCTAssertEqual(editor.annotations,[second])
    }
    func testWholeMoveOrResizeGestureUsesOneHistoryStep() {
        let original=mark(5)
        var editor=ImageAnnotationEditorState();editor.reset([original]);editor.beginInteraction()
        for x in 6...100 {editor.move(at:0,rect:mark(Double(x)).rect,points:mark(Double(x)).points)}
        editor.endInteraction();XCTAssertTrue(editor.canUndo)
        let moved=editor.annotations
        editor.undo();XCTAssertEqual(editor.annotations,[original]);XCTAssertFalse(editor.canUndo)
        editor.redo();XCTAssertEqual(editor.annotations,moved)
        XCTAssertEqual(editor.annotations[0].text,original.text);XCTAssertEqual(editor.annotations[0].opacity,0.7)
    }
    func testClearAndDivergingEditsKeepCorrectRedoHistory() {
        var editor=ImageAnnotationEditorState();editor.reset([mark(5),mark(50)])
        editor.clear();editor.undo();XCTAssertEqual(editor.annotations.count,2);XCTAssertTrue(editor.canRedo)
        editor.remove(at:1);XCTAssertFalse(editor.canRedo);editor.undo();XCTAssertEqual(editor.annotations.count,2)
        editor.clear();editor.undo();editor.redo();XCTAssertTrue(editor.annotations.isEmpty)
    }
    func testInvalidActionsAndNoOpDragPreserveRedo() {
        var editor=ImageAnnotationEditorState();editor.append(mark(5));editor.undo()
        editor.remove(at:-1);editor.remove(at:0);editor.clear();editor.move(at:0,rect:mark(5).rect,points:[])
        editor.beginInteraction();editor.endInteraction()
        XCTAssertFalse(editor.canUndo);XCTAssertTrue(editor.canRedo)
        editor.redo();editor.beginInteraction();editor.move(at:0,rect:mark(5).rect,points:mark(5).points);editor.endInteraction()
        editor.undo();XCTAssertTrue(editor.annotations.isEmpty)
    }
    func testResetAndHistoryBoundPreventPreviousDocumentEdits() {
        var editor=ImageAnnotationEditorState()
        for x in 0..<75 {editor.append(mark(Double(x)))}
        var undos=0
        while editor.canUndo {editor.undo();undos+=1}
        XCTAssertEqual(undos,50);XCTAssertEqual(editor.annotations.count,25)
        editor.reset([mark(200)]);editor.undo();editor.redo()
        XCTAssertEqual(editor.annotations,[mark(200)]);XCTAssertFalse(editor.canUndo);XCTAssertFalse(editor.canRedo)
    }
    func testUndoDuringActiveDragCommitsAndReversesIt() {
        var editor=ImageAnnotationEditorState();editor.reset([mark(5)])
        editor.beginInteraction();editor.move(at:0,rect:mark(80).rect,points:mark(80).points)
        editor.undo();XCTAssertEqual(editor.annotations,[mark(5)])
        editor.redo();XCTAssertEqual(editor.annotations,[mark(80)])
    }
}
