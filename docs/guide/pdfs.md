# Working with PDFs

[Back to Twister](../../README.md)

## Arrange pages

Open a single PDF with **Organize PDF** to reorder, rotate, duplicate or delete pages. Review the page sequence before exporting. Twister writes an organized copy, so the source PDF remains available if you want to start again.

## Undo page changes

Use the organizer controls, the native Edit menu or ⌘Z and ⇧⌘Z. Undo restores page order, rotations and selection, with a limit of 50 page edits. Selecting a page alone does not consume an edit; a new edit clears Redo, and replacing the document resets history.

## Enter page ranges

Page ranges use visible page numbers starting at 1. A value such as `1,3-5` selects pages 1, 3, 4 and 5; `5-3` selects pages in reverse order. Empty ranges select all pages. In **Split PDF**, the pages-per-file value groups the selected sequence into separate outputs.

## Merge several PDFs

Select multiple PDFs to make **Merge PDFs** available. The merge uses the input sequence and adds every page from each selected document. Check the resulting page order, especially when filenames are similar; merging exports a new document rather than appending pages to an original file.

## Export pages as images

Convert a PDF to PNG or JPEG to render its pages into a separate output folder. The renderer includes page rotation and annotations. Higher DPI produces larger images and uses more memory; if a page is too large to render, reduce the requested DPI and try again.

## Choose compression carefully

**Compress** writes a separate PDF. The compression path depends on document content and on features that must be preserved, so the size reduction varies between files. Compare the result with the original for text readability, page appearance and any interactive features you rely on.

## Open protected documents

Supply the password when a PDF is locked. Some combinations of encryption, form fields, attachments or links cannot be safely preserved by a page operation; Twister rejects those exports. Uniform page width also refuses documents with unsupported preservation requirements, so try leaving that option off.
