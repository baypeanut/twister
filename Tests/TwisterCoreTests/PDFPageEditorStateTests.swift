import XCTest
import PDFKit
@testable import TwisterCore

final class PDFPageEditorStateTests:XCTestCase {
    private func document(pages:Int)->PDFDocument {
        let document=PDFDocument()
        for index in 0..<pages { document.insert(PDFPage(),at:index) }
        return document
    }
    private func assertEditor(_ editor:PDFPageEditorState,sources:[Int],rotations:[Int],selection:Int?,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertEqual(editor.sourceIndexes,sources,file:file,line:line)
        XCTAssertEqual(editor.pages.map(\.rotation),rotations,file:file,line:line)
        XCTAssertEqual(editor.selectedPage,selection,file:file,line:line)
    }
    func testResetAfterDuplicatingClearsOutOfRangeSelection() {
        let original=document(pages:2)
        var editor=PDFPageEditorState();editor.reset(document:original)
        editor.select(1);editor.duplicateSelected();editor.select(2);editor.duplicateSelected();editor.select(3)
        XCTAssertEqual(editor.pages.count,4)
        editor.reset(document:original)
        XCTAssertNil(editor.selectedPage)
        editor.rotateSelected();editor.duplicateSelected();editor.deleteSelected();editor.moveSelected(by:-1)
        XCTAssertEqual(editor.pages.count,2)
        XCTAssertEqual(editor.sourceIndexes,[0,1])
        XCTAssertEqual(editor.pages.map(\.rotation),[0,0])
    }
    func testReorderingKeepsSourceAndRotationAttachedToEachPage() {
        var editor=PDFPageEditorState();editor.reset(document:document(pages:3))
        editor.select(1);editor.rotateSelected();editor.duplicateSelected();editor.select(2);editor.moveSelected(by:1)
        XCTAssertEqual(editor.sourceIndexes,[0,1,2,1])
        XCTAssertEqual(editor.rotations,[0:0,1:90,2:0,3:90])
        editor.deleteSelected()
        XCTAssertEqual(editor.sourceIndexes,[0,1,2])
        XCTAssertNil(editor.selectedPage)
    }
    func testInvalidSelectionAndDocumentReplacementCannotMutateOtherPages() {
        var editor=PDFPageEditorState();editor.reset(document:document(pages:1))
        editor.select(Int.max);editor.rotateSelected();editor.duplicateSelected();editor.deleteSelected();editor.moveSelected(by:1)
        XCTAssertNil(editor.selectedPage)
        editor.select(0);editor.deleteSelected();editor.moveSelected(by:-1);editor.moveSelected(by:1)
        XCTAssertEqual(editor.pages.count,1)
        editor.reset()
        XCTAssertTrue(editor.pages.isEmpty)
        XCTAssertTrue(editor.sourceIndexes.isEmpty)
        XCTAssertFalse(editor.hasSelection)
    }

    func testUndoRedoRestoresPageIdentityRotationAndSelectionAcrossAllEdits() {
        let original=document(pages:3)
        let originalRotations=[0,90,180]
        let originalBounds:[CGRect]=(0..<3).map { index in
            let width=CGFloat(200+index*20),height=CGFloat(300+index*30)
            return CGRect(x:0,y:0,width:width,height:height)
        }
        for index in 0..<3 {
            original.page(at:index)?.rotation=originalRotations[index]
            original.page(at:index)?.setBounds(originalBounds[index],for:.mediaBox)
        }
        var editor=PDFPageEditorState();editor.reset(document:original)
        editor.select(1);editor.rotateSelected();editor.duplicateSelected()
        editor.select(2);editor.moveSelected(by:1);editor.deleteSelected()
        assertEditor(editor,sources:[0,1,2],rotations:[0,180,180],selection:nil)

        editor.undo()
        assertEditor(editor,sources:[0,1,2,1],rotations:[0,180,180,180],selection:3)
        editor.undo()
        assertEditor(editor,sources:[0,1,1,2],rotations:[0,180,180,180],selection:2)
        editor.undo()
        assertEditor(editor,sources:[0,1,2],rotations:[0,180,180],selection:1)
        editor.undo()
        assertEditor(editor,sources:[0,1,2],rotations:originalRotations,selection:1)
        XCTAssertFalse(editor.canUndo)
        XCTAssertTrue(editor.canRedo)

        for _ in 0..<4 { editor.redo() }
        assertEditor(editor,sources:[0,1,2],rotations:[0,180,180],selection:nil)
        XCTAssertTrue(editor.canUndo)
        XCTAssertFalse(editor.canRedo)
        for (index,page) in editor.pages.enumerated() {
            XCTAssertEqual(page.bounds(for:.mediaBox),originalBounds[editor.sourceIndexes[index]])
        }
        XCTAssertEqual(original.pageCount,3)
        XCTAssertEqual((0..<3).map { original.page(at:$0)!.rotation },originalRotations)
        XCTAssertEqual((0..<3).map { original.page(at:$0)!.bounds(for:.mediaBox) },originalBounds)
    }

    func testRestoredDuplicateRotatesIndependentlyOfItsSiblingAndSource() {
        let original=document(pages:1)
        var editor=PDFPageEditorState();editor.reset(document:original)
        editor.select(0);editor.duplicateSelected();editor.select(1);editor.rotateSelected()
        editor.undo()
        assertEditor(editor,sources:[0,0],rotations:[0,0],selection:1)
        editor.redo()
        assertEditor(editor,sources:[0,0],rotations:[0,90],selection:1)
        editor.select(0);editor.rotateSelected();editor.rotateSelected()
        assertEditor(editor,sources:[0,0],rotations:[180,90],selection:0)
        XCTAssertEqual(original.pageCount,1)
        XCTAssertEqual(original.page(at:0)?.rotation,0)
    }

    func testInvalidAndNoOpActionsDoNotCreateHistoryOrDiscardRedo() {
        var editor=PDFPageEditorState();editor.reset(document:document(pages:1))
        editor.select(0);editor.rotateSelected();editor.undo()
        XCTAssertFalse(editor.canUndo)
        XCTAssertTrue(editor.canRedo)
        editor.deleteSelected()
        for offset in [-1,0,1,2,Int.max] { editor.moveSelected(by:offset) }
        editor.select(Int.max);editor.rotateSelected();editor.duplicateSelected();editor.deleteSelected();editor.moveSelected(by:1)
        editor.select(0);editor.undo()
        XCTAssertFalse(editor.canUndo)
        XCTAssertTrue(editor.canRedo)
        assertEditor(editor,sources:[0],rotations:[0],selection:0)
        editor.redo();editor.redo()
        assertEditor(editor,sources:[0],rotations:[90],selection:0)
        XCTAssertTrue(editor.canUndo)
        XCTAssertFalse(editor.canRedo)
    }

    func testNewPageEditClearsRedoButChangingSelectionDoesNot() {
        var editor=PDFPageEditorState();editor.reset(document:document(pages:2))
        editor.select(0);editor.rotateSelected();editor.undo();editor.select(1)
        XCTAssertTrue(editor.canRedo)
        editor.rotateSelected()
        XCTAssertFalse(editor.canRedo)
        editor.redo()
        assertEditor(editor,sources:[0,1],rotations:[0,90],selection:1)
        editor.undo()
        assertEditor(editor,sources:[0,1],rotations:[0,0],selection:1)
        XCTAssertFalse(editor.canUndo)
    }

    func testResetAndDocumentReplacementDiscardBothHistoryStacks() {
        var editor=PDFPageEditorState();editor.reset(document:document(pages:2))
        editor.select(0);editor.rotateSelected();editor.duplicateSelected();editor.undo()
        XCTAssertTrue(editor.canUndo)
        XCTAssertTrue(editor.canRedo)
        let replacement=document(pages:1);replacement.page(at:0)?.rotation=270
        editor.reset(document:replacement);editor.undo();editor.redo()
        assertEditor(editor,sources:[0],rotations:[270],selection:nil)
        XCTAssertFalse(editor.canUndo)
        XCTAssertFalse(editor.canRedo)
        editor.select(0);editor.duplicateSelected();editor.undo()
        editor.reset();editor.undo();editor.redo()
        XCTAssertTrue(editor.pages.isEmpty)
        XCTAssertTrue(editor.sourceIndexes.isEmpty)
        XCTAssertNil(editor.selectedPage)
        XCTAssertFalse(editor.canUndo)
        XCTAssertFalse(editor.canRedo)
    }

    func testHistoryRetainsOnlyTheLastFiftyEdits() {
        let original=document(pages:1)
        var editor=PDFPageEditorState();editor.reset(document:original);editor.select(0)
        for _ in 0..<75 { editor.rotateSelected() }
        var undoCount=0
        while editor.canUndo,undoCount<100 { editor.undo();undoCount+=1 }
        XCTAssertEqual(undoCount,50)
        assertEditor(editor,sources:[0],rotations:[90],selection:0)
        var redoCount=0
        while editor.canRedo,redoCount<100 { editor.redo();redoCount+=1 }
        XCTAssertEqual(redoCount,50)
        assertEditor(editor,sources:[0],rotations:[270],selection:0)
        XCTAssertFalse(editor.canRedo)
        XCTAssertEqual(original.page(at:0)?.rotation,0)
    }

    func testCopiedEditorHasIndependentEditsAndHistory() {
        var editor=PDFPageEditorState();editor.reset(document:document(pages:1))
        editor.select(0);editor.rotateSelected()
        var copy=editor
        copy.duplicateSelected();copy.select(1);copy.rotateSelected()
        editor.undo()
        assertEditor(editor,sources:[0],rotations:[0],selection:0)
        assertEditor(copy,sources:[0,0],rotations:[90,180],selection:1)
        copy.undo();copy.undo()
        assertEditor(copy,sources:[0],rotations:[90],selection:0)
        editor.redo()
        assertEditor(editor,sources:[0],rotations:[90],selection:0)
    }
}
