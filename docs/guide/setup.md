# Optional tools

[Back to Twister](../../README.md)

## Install only what you need

Setup separates optional tools into Media and Office groups. Media readiness checks FFmpeg, FFprobe, yt-dlp and Deno; Office readiness checks LibreOffice. You can return to the workspace without installing either group and add missing tools when a conversion needs them.

## Reuse an installed tool

Twister checks supported existing tool locations before asking for an installation. A tool must resolve to a nonempty executable file, not just a directory with the same name. Standard locations include Homebrew paths and the normal LibreOffice application location.
