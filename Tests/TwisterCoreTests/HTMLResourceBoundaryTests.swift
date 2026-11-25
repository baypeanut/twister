import XCTest
import AppKit
@testable import TwisterCore
final class HTMLResourceBoundaryTests:XCTestCase {
    func testRemoteOutsideAndUnquotedResourcesAreExcluded() throws {
        let fm=FileManager.default;let root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true);defer{try? fm.removeItem(at:root)}
        let input=root.appendingPathComponent("test.html")
        try "<link href='file:///outside.css'><style>@import 'https://example.com/x.css';x{background:url(file:///private/data.png)}</style><img src=file:///private/data.png><img src='https://example.com/a.png'><img src=../outside.png>".write(to:input,atomically:true,encoding:.utf8)
        try DocumentEngine.embedHTMLImages(input,token:.init())
        let output=try String(contentsOf:input,encoding:.utf8)
        XCTAssertFalse(output.contains("file:"));XCTAssertFalse(output.contains("https:"));XCTAssertFalse(output.contains("../"));XCTAssertFalse(output.contains("<link"))
    }

    func testContainmentAcceptsOnlyItemsStrictlyInsideTheFolder() throws {
        let fm=FileManager.default;let parent=try OutputFiles.temporaryDirectory();defer{try? fm.removeItem(at:parent)}
        let root=parent.appendingPathComponent("Rich text resources",isDirectory:true),sibling=parent.appendingPathComponent("Rich text resources 2",isDirectory:true)
        try fm.createDirectory(at:root,withIntermediateDirectories:true);try fm.createDirectory(at:sibling,withIntermediateDirectories:true)
        try Data("png".utf8).write(to:root.appendingPathComponent("image.png"));try Data("secret".utf8).write(to:sibling.appendingPathComponent("secret.png"))
        try fm.createSymbolicLink(at:root.appendingPathComponent("escape.png"),withDestinationURL:sibling.appendingPathComponent("secret.png"))
        XCTAssertEqual(PathContainment.resolved(root.appendingPathComponent("image.png"),inside:root)?.lastPathComponent,"image.png")
        for name in ["../Rich text resources 2/secret.png","escape.png",".","..","sub/../../x.png"] {
            XCTAssertNil(PathContainment.resolved(root.appendingPathComponent(name),inside:root),name)
        }
        XCTAssertNil(PathContainment.resolved(root,inside:root))
        XCTAssertNil(PathContainment.resolved(URL(fileURLWithPath:"/etc/hosts"),inside:URL(fileURLWithPath:"/")))
    }

    func testRichTextAttachmentsResolveOnlyBesideTheirHTML() throws {
        let fm=FileManager.default;let work=try OutputFiles.temporaryDirectory();defer{try? fm.removeItem(at:work)}
        let image=NSImage(size:NSSize(width:4,height:4));image.lockFocus();NSColor.red.setFill();NSRect(x:0,y:0,width:4,height:4).fill();image.unlockFocus()
        let attachment=NSTextAttachment();attachment.fileWrapper=FileWrapper(regularFileWithContents:try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(image.tiffRepresentation))?.representation(using:.png,properties:[:])))
        attachment.fileWrapper?.preferredFilename="dot.png"
        let text=NSMutableAttributedString(string:"Before ");text.append(NSAttributedString(attachment:attachment))
        let rtfd=work.appendingPathComponent("Note.rtfd")
        try text.fileWrapper(from:NSRange(location:0,length:text.length),documentAttributes:[.documentType:NSAttributedString.DocumentType.rtfd]).write(to:rtfd,options:.atomic,originalContentsURL:nil)
        let html=try RichTextCodec.materializeHTML(rtfd,in:work)
        let output=try String(contentsOf:html,encoding:.utf8)
        let folder=html.deletingLastPathComponent().resolvingSymlinksInPath().path
        let pattern=try NSRegularExpression(pattern:#"src\s*=\s*["'](file:[^"']+)["']"#)
        for match in pattern.matches(in:output,range:NSRange(output.startIndex...,in:output)) {
            let url=try XCTUnwrap(URL(string:(output as NSString).substring(with:match.range(at:1))))
            XCTAssertTrue(url.resolvingSymlinksInPath().path.hasPrefix(folder+"/"),url.path)
        }
    }
}
