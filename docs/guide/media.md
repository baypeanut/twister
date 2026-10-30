# Working with media

[Back to Twister](../../README.md)

## Prepare media tools

Audio and video conversions, inspection and previews use FFmpeg and FFprobe. Open setup if the required tools are missing. A custom installation can provide different encoders, so an available file extension alone does not establish that every requested export profile can be encoded.

## Choose a trim range

Use the range handles or the start and end controls to set the portion you want to keep. Space controls preview playback, while I and O mark selection endpoints in the media editor. Check that the range has a positive duration and stays inside the source before exporting.

## Move the playhead deliberately

Seeking changes the preview position; dragging a range handle changes an export boundary. Dragging inside a selected range moves that range while preserving its length. Use the boundary controls when you want an exact cut instead of treating every timeline click as a trim edit.

## Split a video

**Split Video** can use chosen split points, an equal clip count or a fixed interval. Boundaries must fall within the video and leave at least 0.05 seconds between adjacent cuts and either end. Very short sources or dense cuts can therefore be rejected even when the requested count looks reasonable.

## Keep the clips you need

Remove unwanted segments from the split selection before exporting. At least one segment must remain. Separate exports keep retained clips in their original timeline order and place them in a new clips folder; a failed export removes its unfinished folder.
