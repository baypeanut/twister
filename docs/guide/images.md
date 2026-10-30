# Working with images

[Back to Twister](../../README.md)

## Choose an image conversion

Common image routes include JPEG, PNG, WebP, HEIC, TIFF, AVIF, BMP and PDF. The choices shown for your selection are the supported routes, rather than every possible image format. Some encoders require optional media tools; a format being listed does not mean its required runtime is already installed.

## Crop inside the source

Use **Crop Image** to choose the portion of an image to keep. The crop must fit within the source image. For a batch, the requested rectangle must be valid for every image; a crop that fits a large photo may be outside a smaller one, and the failed batch does not publish partial results.

## Set the export dimensions

Cropping selects an area; resizing controls the dimensions of the exported image. Check both settings when an output has the right subject but the wrong size. An explicit resize remains part of a crop export, so reset dimensions you no longer want before saving.

## Undo an annotation edit

The annotation editor supports ⌘Z and ⇧⌘Z for Undo and Redo. A complete drag is one edit, even if the pointer moves many times. History keeps up to 50 edits; a new edit clears Redo, and replacing the annotation state starts a new history.

## Review redacted regions

**Redact Photo** offers solid, blur and pixelate styles, with optional face and text detection. Review the selected regions and the exported image before sharing it. Detection can miss content, and changing pixels does not by itself remove metadata stored in the file.

## Build a collage

Select several supported images and choose **Create Collage**. Layouts include grid, row, column and featured. Fit keeps the whole source inside a cell; Fill fills the cell and may crop its edges. Check image order, canvas dimensions, spacing and padding before exporting.
