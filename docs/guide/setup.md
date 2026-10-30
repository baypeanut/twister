# Optional tools

[Back to Twister](../../README.md)

## Install only what you need

Setup separates optional tools into Media and Office groups. Media readiness checks FFmpeg, FFprobe, yt-dlp and Deno; Office readiness checks LibreOffice. You can return to the workspace without installing either group and add missing tools when a conversion needs them.

## Reuse an installed tool

Twister checks supported existing tool locations before asking for an installation. A tool must resolve to a nonempty executable file, not just a directory with the same name. Standard locations include Homebrew paths and the normal LibreOffice application location.

## Know what setup downloads

Optional tool packages come from pinned HTTPS sources and are checked against SHA-256 values. Downloads are prepared in staging before a complete installation is published. Installed tool storage is `~/Library/Application Support/Twister/Tools`; setup needs a network connection, while completed local conversions use the installed tools.

## Cancel or retry setup

Cancel stops the current setup work and keeps tools that were already usable. If one tool group completed before another failed, its installation remains available. Return to setup to retry the missing group; an interrupted download does not require deleting a working installation.

## Use an explicit executable

For development or troubleshooting, set the relevant environment variable before launching the CLI or app from that environment. Supported overrides include `TWISTER_FFMPEG`, `TWISTER_FFPROBE`, `TWISTER_EXIFTOOL` and `TWISTER_SOFFICE`. Point each value at the executable file, and check CLI resolution with `twister-cli dependencies` once the conversion dependencies are available.
